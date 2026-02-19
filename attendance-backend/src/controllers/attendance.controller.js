const { supabaseAdmin } = require('../utils/supabase');
const { verifyDeviceSignature } = require('../utils/security');

/**
 * 📥 1. Initial Check-In (Provisional)
 * + Device Binding: locks device_id to student on first check-in
 */
exports.checkIn = async (req, res) => {
  try {
    const { studentId, classId, sessionId, deviceId, deviceSignature, rssi, reportedMinor } = req.body;

    // 1. Verify Device Signature
    const { valid } = verifyDeviceSignature({ deviceId, signature: deviceSignature });
    if (!valid) return res.status(401).json({ error: 'Invalid device signature' });

    // 2. Device Binding Check
    const { data: student } = await supabaseAdmin
      .from('students').select('device_id').eq('student_id', studentId).single();

    if (student?.device_id && student.device_id !== deviceId) {
      return res.status(403).json({
        error: 'Device mismatch',
        message: 'This account is bound to a different device. Contact your teacher to reset.'
      });
    }

    // Bind device on first check-in
    if (!student?.device_id) {
      await supabaseAdmin.from('students').update({ device_id: deviceId }).eq('student_id', studentId);
      console.log(`🔐 Device bound: ${studentId} → ${deviceId.substring(0, 8)}...`);
    }

    // 3. Get session
    const { data: session } = await supabaseAdmin
      .from('sessions')
      .select('status, current_minor_id, beacon_minor, last_rotation_at, rotation_interval_mins')
      .eq('id', sessionId).single();

    if (!session || session.status !== 'active') {
      return res.status(403).json({ error: 'No active session found for this class' });
    }

    // 4. Minor ID Validation
    const expectedMinor = session.current_minor_id ?? session.beacon_minor;
    if (reportedMinor !== expectedMinor) {
      return res.status(403).json({ error: 'Invalid Beacon ID', message: 'Minor mismatch' });
    }

    // 5. Rotation expiry check
    if (session.last_rotation_at && session.rotation_interval_mins) {
      const diffMin = (new Date() - new Date(session.last_rotation_at)) / 60000;
      if (diffMin > session.rotation_interval_mins) {
        return res.status(403).json({ error: 'Beacon Expired', message: 'Wait for next rotation' });
      }
    }

    // 6. Create provisional record
    const { data: attendance, error } = await supabaseAdmin
      .from('attendance')
      .insert({
        student_id: studentId, class_id: classId, session_id: sessionId,
        device_id: deviceId, status: 'provisional', rssi: rssi || -70,
        beacon_minor: reportedMinor, session_date: new Date().toISOString().split('T')[0]
      })
      .select().single();

    if (error && error.code === '23505') return res.status(200).json({ message: 'Already checked in' });
    if (error) throw error;

    console.log(`✅ Check-in: Student ${studentId} Minor ${reportedMinor}`);
    res.status(201).json({ success: true, status: 'provisional', attendance });
  } catch (error) {
    console.error('❌ Check-in error:', error);
    res.status(500).json({ error: 'Failed to record check-in' });
  }
};

/**
 * 📡 2. Continuous RSSI Upload (45-min Analysis)
 * Receives periodic signal data for proxy detection.
 */
exports.uploadRssiStream = async (req, res) => {
  try {
    const { studentId, classId, rssiData } = req.body;
    const today = new Date().toISOString().split('T')[0];

    // Append to JSONB array in rssi_streams table
    const { data: stream } = await supabaseAdmin
      .from('rssi_streams')
      .select('id, rssi_data')
      .eq('student_id', studentId)
      .eq('class_id', classId)
      .eq('session_date', today)
      .single();

    if (stream) {
      const updatedData = [...stream.rssi_data, ...rssiData];
      await supabaseAdmin.from('rssi_streams').update({ 
        rssi_data: updatedData, 
        sample_count: updatedData.length 
      }).eq('id', stream.id);
    } else {
      await supabaseAdmin.from('rssi_streams').insert({
        student_id: studentId,
        class_id: classId,
        session_date: today,
        rssi_data: rssiData,
        sample_count: rssiData.length
      });
    }

    res.status(200).json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to upload RSSI stream' });
  }
};

/**
 * 🔒 3. Final Physical/Biometric Lock
 */
exports.finalizeVerification = async (req, res) => {
  try {
    const { attendanceId, teacherId, verificationType } = req.body;
    const { data, error } = await supabaseAdmin
      .from('attendance')
      .update({
        status: 'confirmed', confirmed_at: new Date().toISOString(),
        biometric_verified_at: verificationType === 'biometric' ? new Date().toISOString() : null,
        physical_verified_by: teacherId
      })
      .eq('id', attendanceId).select().single();
    if (error) throw error;
    res.status(200).json({ success: true, attendance: data });
  } catch (error) {
    res.status(500).json({ error: 'Final verification failed' });
  }
};

/**
 * 🔄 4. Step-2 Verification (2-Step Attendance)
 * Student reports a NEW minor after beacon rotation → provisional → confirmed
 */
exports.verifyStep2 = async (req, res) => {
  try {
    const { studentId, sessionId, reportedMinor } = req.body;

    // Get current session minor
    const { data: session } = await supabaseAdmin
      .from('sessions')
      .select('current_minor_id, beacon_minor, status')
      .eq('id', sessionId).maybeSingle();

    if (!session || session.status !== 'active') {
      return res.status(404).json({ error: 'Session ended' });
    }

    const expectedMinor = session.current_minor_id ?? session.beacon_minor;
    if (reportedMinor !== expectedMinor) {
      return res.status(403).json({ error: 'Minor mismatch', message: 'Step-2 failed' });
    }

    // Get the student's provisional attendance for this session
    const { data: att } = await supabaseAdmin
      .from('attendance')
      .select('id, status, beacon_minor')
      .eq('student_id', studentId).eq('session_id', sessionId).maybeSingle();

    if (!att) return res.status(404).json({ error: 'No check-in found' });
    if (att.status === 'confirmed') return res.status(200).json({ message: 'Already confirmed' });

    // The reported minor must be DIFFERENT from the one used at check-in (proves continued presence)
    if (reportedMinor === att.beacon_minor) {
      return res.status(403).json({ error: 'Same minor as check-in', message: 'Wait for beacon rotation' });
    }

    // Confirm!
    await supabaseAdmin.from('attendance').update({
      status: 'confirmed', confirmed_at: new Date().toISOString()
    }).eq('id', att.id);

    console.log(`✅ Step-2 confirmed: ${studentId} (minor ${att.beacon_minor} → ${reportedMinor})`);
    res.status(200).json({ success: true, status: 'confirmed' });
  } catch (error) {
    console.error('❌ Step-2 error:', error);
    res.status(500).json({ error: 'Step-2 verification failed' });
  }
};

/**
 * 🔓 5. Reset Device Binding (Teacher only)
 */
exports.resetDevice = async (req, res) => {
  try {
    const { studentId } = req.body;
    const { error } = await supabaseAdmin
      .from('students').update({ device_id: null }).eq('student_id', studentId);
    if (error) throw error;
    console.log(`🔓 Device reset: ${studentId}`);
    res.status(200).json({ success: true });
  } catch (error) {
    res.status(500).json({ error: 'Failed to reset device' });
  }
};

/**
 * 🔐 6. Biometric Fallback Confirmation
 * Student self-confirms via fingerprint when step-2 times out
 */
exports.biometricConfirm = async (req, res) => {
  try {
    const { studentId, sessionId, deviceId } = req.body;

    // Verify device still matches
    const { data: student } = await supabaseAdmin
      .from('students').select('device_id').eq('student_id', studentId).single();
    if (student?.device_id && student.device_id !== deviceId) {
      return res.status(403).json({ error: 'Device mismatch' });
    }

    const { data: att } = await supabaseAdmin
      .from('attendance')
      .select('id, status')
      .eq('student_id', studentId).eq('session_id', sessionId).maybeSingle();

    if (!att) return res.status(404).json({ error: 'No check-in found' });
    if (att.status === 'confirmed') return res.status(200).json({ message: 'Already confirmed' });

    await supabaseAdmin.from('attendance').update({
      status: 'confirmed', confirmed_at: new Date().toISOString(),
      biometric_verified_at: new Date().toISOString()
    }).eq('id', att.id);

    console.log(`🔐 Biometric confirmed: ${studentId}`);
    res.status(200).json({ success: true, status: 'confirmed' });
  } catch (error) {
    console.error('❌ Biometric confirm error:', error);
    res.status(500).json({ error: 'Biometric confirmation failed' });
  }
};