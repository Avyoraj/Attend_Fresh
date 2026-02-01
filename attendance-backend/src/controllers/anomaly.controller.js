const { supabaseAdmin } = require('../utils/supabase');

exports.getPendingAnomalies = async (req, res) => {
  const { classId } = req.query;
  const { data, error } = await supabaseAdmin
    .from('anomalies')
    .select('*')
    .eq('class_id', classId)
    .eq('status', 'pending');

  if (error) return res.status(500).json({ error: error.message });
  res.status(200).json(data);
};