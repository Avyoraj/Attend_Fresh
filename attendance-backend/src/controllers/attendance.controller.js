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
    if (att.status === 'confirmed' || att.status === 'step2_verified') {
      return res.status(200).json({ message: 'Already confirmed' });
    }

    // The reported minor must be DIFFERENT from the one used at check-in (proves continued presence)
    if (reportedMinor === att.beacon_minor) {
      return res.status(403).json({ error: 'Same minor as check-in', message: 'Wait for beacon rotation' });
    }

    // Step-2 passed → mark as step2_verified (NOT confirmed — that comes after analysis)
    await supabaseAdmin.from('attendance').update({
      status: 'step2_verified', step2_verified_at: new Date().toISOString()
    }).eq('id', att.id);

    console.log(`✅ Step-2 verified: ${studentId} (minor ${att.beacon_minor} → ${reportedMinor})`);
    res.status(200).json({ success: true, status: 'step2_verified' });
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

/**
 * 📊 7. Analyze Spot Check Data (5-Min Gold Window)
 * Runs jitter + motion + correlation analysis on collected RSSI streams.
 * Returns: confirmed (all clear) or flagged (suspicious).
 */
exports.analyzeSpotChecks = async (req, res) => {
  try {
    const { studentId, sessionId, classId } = req.body;
    const today = new Date().toISOString().split('T')[0];

    // 1. Get this student's RSSI stream
    const { data: stream } = await supabaseAdmin
      .from('rssi_streams')
      .select('rssi_data')
      .eq('student_id', studentId)
      .eq('class_id', classId)
      .eq('session_date', today)
      .maybeSingle();

    if (!stream || !stream.rssi_data || stream.rssi_data.length === 0) {
      // No data collected → inconclusive, let biometric handle it
      console.log(`⚠️ Analyze: No RSSI data for ${studentId} — inconclusive`);
      return res.status(200).json({ status: 'inconclusive', reason: 'No spot check data received' });
    }

    const readings = stream.rssi_data;
    const validReadings = readings.filter(r => !r.missed);
    const missedCount = readings.filter(r => r.missed).length;

    // 2. Check for missed spot checks (app killed / student left)
    if (missedCount >= 2) {
      console.log(`🚩 Analyze: ${studentId} missed ${missedCount} spot checks — flagged`);
      await supabaseAdmin.from('attendance').update({ status: 'flagged' })
        .eq('student_id', studentId).eq('session_id', sessionId);
      return res.status(200).json({ status: 'flagged', reason: 'Missed spot checks' });
    }

    // 3. Motion analysis — was the phone actually being held?
    const motionCount = validReadings.filter(r => r.hasMotion === true).length;
    const motionRatio = validReadings.length > 0 ? motionCount / validReadings.length : 0;

    // 4. Jitter analysis — RSSI variation (phone on desk = near-zero jitter)
    let jitter = 0;
    if (validReadings.length >= 2) {
      const rssiValues = validReadings.map(r => r.rssi);
      const diffs = rssiValues.slice(1).map((v, i) => Math.abs(v - rssiValues[i]));
      jitter = diffs.reduce((a, b) => a + b, 0) / diffs.length;
    }

    // 5. Scoring
    let riskScore = 0;
    let reasons = [];

    // Static device: no motion + low jitter = phone on desk
    if (motionRatio < 0.3) { riskScore += 40; reasons.push('Low motion detected'); }
    if (jitter < 0.5 && validReadings.length >= 3) { riskScore += 30; reasons.push('Static RSSI (desk?)'); }
    if (missedCount >= 1) { riskScore += 20; reasons.push('Missed a spot check'); }

    // 6. Pairwise correlation (if other students have streams for this session)
    const { data: allStreams } = await supabaseAdmin
      .from('rssi_streams')
      .select('student_id, rssi_data')
      .eq('class_id', classId)
      .eq('session_date', today)
      .neq('student_id', studentId);

    if (allStreams && allStreams.length > 0) {
      const myRssi = validReadings.map(r => r.rssi);
      for (const other of allStreams) {
        const otherValid = (other.rssi_data || []).filter(r => !r.missed);
        if (otherValid.length < 3) continue;
        const otherRssi = otherValid.map(r => r.rssi);

        const len = Math.min(myRssi.length, otherRssi.length);
        if (len < 3) continue;

        // Pearson correlation
        const x = myRssi.slice(0, len), y = otherRssi.slice(0, len);
        const muX = x.reduce((a, b) => a + b, 0) / len;
        const muY = y.reduce((a, b) => a + b, 0) / len;
        let num = 0, sqX = 0, sqY = 0;
        for (let i = 0; i < len; i++) {
          num += (x[i] - muX) * (y[i] - muY);
          sqX += (x[i] - muX) ** 2;
          sqY += (y[i] - muY) ** 2;
        }
        const denom = Math.sqrt(sqX * sqY);
        const pearson = denom === 0 ? 0 : num / denom;

        if (pearson > 0.85) {
          riskScore += 50;
          reasons.push(`High correlation (${pearson.toFixed(2)}) with ${other.student_id}`);
          break; // One high correlation is enough
        }
      }
    }

    // 7. Verdict
    const isFlagged = riskScore >= 60;
    const newStatus = isFlagged ? 'flagged' : 'confirmed';

    await supabaseAdmin.from('attendance').update({
      status: newStatus,
      ...(newStatus === 'confirmed' ? { confirmed_at: new Date().toISOString() } : {})
    }).eq('student_id', studentId).eq('session_id', sessionId);

    console.log(`📊 Analyze: ${studentId} → ${newStatus} (risk=${riskScore}, reasons=${reasons.join(', ')})`);
    res.status(200).json({ status: newStatus, riskScore, reasons });
  } catch (error) {
    console.error('❌ Analyze error:', error);
    res.status(500).json({ error: 'Analysis failed' });
  }
};