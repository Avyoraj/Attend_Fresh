const { supabaseAdmin } = require('../utils/supabase');
const { verifyDeviceSignature } = require('../utils/security');

/**
 * 📥 1. Initial Check-In (Provisional)
 * Marks a student as present but unverified.
 * Now includes Dynamic Minor ID Validation ("Human Presence" Check)
 */
exports.checkIn = async (req, res) => {
  try {
    const { studentId, classId, sessionId, deviceId, deviceSignature, rssi, reportedMinor } = req.body;

    // 1. Verify Device Signature (Security Gate)
    const { valid } = verifyDeviceSignature({ deviceId, signature: deviceSignature });
    if (!valid) return res.status(401).json({ error: 'Invalid device signature' });

    // 2. Get session with dynamic beacon info
    const { data: session } = await supabaseAdmin
      .from('sessions')
      .select('status, current_minor_id, beacon_minor, last_rotation_at, rotation_interval_mins')
      .eq('id', sessionId)
      .single();

    if (!session || session.status !== 'active') {
      return res.status(403).json({ error: 'No active session found for this class' });
    }

    // 3. 🎯 Dynamic ID Validation (The "Challenge" Gate)
    // Accept if minor matches current_minor_id OR the original beacon_minor (fallback)
    const expectedMinor = session.current_minor_id ?? session.beacon_minor;
    if (reportedMinor !== expectedMinor) {
      return res.status(403).json({ 
        error: 'Invalid Beacon ID', 
        message: `Failed Human Presence Check (ID Mismatch: got ${reportedMinor}, expected ${expectedMinor})` 
      });
    }

    // 4. 🕐 Rotation expiry check (skip if last_rotation_at is null — session just started)
    if (session.last_rotation_at && session.rotation_interval_mins) {
      const now = new Date();
      const lastRotation = new Date(session.last_rotation_at);
      const diffMinutes = (now - lastRotation) / 60000;

      if (diffMinutes > session.rotation_interval_mins) {
        return res.status(403).json({ 
          error: 'Beacon Expired', 
          message: `Please wait for the next beacon rotation (Window: ${session.rotation_interval_mins} min)` 
        });
      }
    }

    // 5. Create provisional record
    const { data: attendance, error } = await supabaseAdmin
      .from('attendance')
      .insert({
        student_id: studentId,
        class_id: classId,
        session_id: sessionId,
        device_id: deviceId,
        status: 'provisional',
        rssi: rssi || -70,
        beacon_minor: reportedMinor, // Store the minor ID used for check-in
        session_date: new Date().toISOString().split('T')[0]
      })
      .select()
      .single();

    if (error && error.code === '23505') return res.status(200).json({ message: 'Already checked in' });
    if (error) throw error;

    console.log(`✅ Check-in: Student ${studentId} with Minor ${reportedMinor}`);
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
 * Moves status to 'confirmed' after fingerprint or headcount.
 */
exports.finalizeVerification = async (req, res) => {
  try {
    const { attendanceId, teacherId, verificationType } = req.body;

    const { data, error } = await supabaseAdmin
      .from('attendance')
      .update({
        status: 'confirmed',
        confirmed_at: new Date().toISOString(),
        biometric_verified_at: verificationType === 'biometric' ? new Date().toISOString() : null,
        physical_verified_by: teacherId
      })
      .eq('id', attendanceId)
      .select()
      .single();

    if (error) throw error;
    res.status(200).json({ success: true, attendance: data });
  } catch (error) {
    res.status(500).json({ error: 'Final verification failed' });
  }
};