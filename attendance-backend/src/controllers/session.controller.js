const { supabaseAdmin } = require('../utils/supabase');

/**
 * 🎯 Start Session (Host Activator)
 * Creates an active session linking a room (beacon) to a class.
 */
exports.startSession = async (req, res) => {
  try {
    const { roomId, classId, className, teacherId, teacherName, beaconMajor, beaconMinor } = req.body;

    if (!roomId || !classId || !teacherId) {
      return res.status(400).json({ error: 'Missing required session parameters' });
    }

    // Create the session in Supabase
    const { data: session, error } = await supabaseAdmin
      .from('sessions')
      .insert({
        room_id: roomId,
        class_id: classId,
        class_name: className,
        teacher_id: teacherId,
        teacher_name: teacherName,
        beacon_major: beaconMajor,
        beacon_minor: beaconMinor,
        status: 'active',
        actual_start: new Date().toISOString()
      })
      .select()
      .single();

    if (error) {
      if (error.code === '23505') { // Unique index violation 
        return res.status(409).json({ error: 'A session is already active in this room' });
      }
      throw error;
    }

    console.log(`📡 Session started: ${className} in ${roomId}`);
    res.status(201).json({ success: true, session });
  } catch (error) {
    console.error('❌ Start session error:', error);
    res.status(500).json({ error: 'Failed to start session' });
  }
};

/**
 * 🏁 End Session
 * Marks a session as ended and records the final time.
 */
exports.endSession = async (req, res) => {
  try {
    const { sessionId } = req.params;

    const { data: session, error } = await supabaseAdmin
      .from('sessions')
      .update({
        status: 'ended',
        actual_end: new Date().toISOString()
      })
      .eq('id', sessionId)
      .select()
      .single();

    if (error || !session) {
      return res.status(404).json({ error: 'Session not found or already ended' });
    }

    console.log(`✅ Session ended: ${session.id}`);
    res.status(200).json({ success: true, session });
  } catch (error) {
    console.error('❌ End session error:', error);
    res.status(500).json({ error: 'Failed to end session' });
  }
};

/**
 * 💓 Sync Minor ID (Heartbeat)
 * Called by the Teacher App when it detects an ESP32 rotation.
 * Updates the expected Minor ID for the 3-minute validation window.
 */
exports.updateSessionMinor = async (req, res) => {
  try {
    const { sessionId, newMinorId } = req.body;

    if (!sessionId || newMinorId === undefined) {
      return res.status(400).json({ error: 'Missing sessionId or newMinorId' });
    }

    const { data, error } = await supabaseAdmin
      .from('sessions')
      .update({
        current_minor_id: newMinorId,
        last_rotation_at: new Date().toISOString()
      })
      .eq('id', sessionId)
      .eq('status', 'active') // Only update active sessions
      .select()
      .single();

    if (error) throw error;

    if (!data) {
      return res.status(404).json({ error: 'Active session not found' });
    }

    console.log(`🔄 DB Synced: Session ${sessionId} now expects Minor ${newMinorId}`);
    res.status(200).json({ success: true, current_minor_id: newMinorId });
  } catch (error) {
    console.error('❌ Sync minor error:', error);
    res.status(500).json({ error: 'Failed to sync Minor ID' });
  }
};