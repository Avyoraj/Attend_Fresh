const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const morgan = require('morgan');
require('dotenv').config();

// Import Routes
const sessionRoutes = require('./routes/session.routes');
const attendanceRoutes = require('./routes/attendance.routes');
const anomalyRoutes = require('./routes/anomaly.routes');

const app = express();
const PORT = process.env.PORT || 5000;

// Middleware
app.use(helmet());
app.use(cors());
app.use(express.json());
app.use(morgan('dev'));

// Register Routes
app.use('/api/sessions', sessionRoutes);      // Host logic (Start/End Class)
app.use('/api/attendance', attendanceRoutes); // Joiner logic (Check-in/RSSI Stream)
app.use('/api/anomalies', anomalyRoutes);    // Analysis logic (Proxy Detection)

// Basic Health Check
app.get('/health', (req, res) => {
  res.status(200).json({ 
    status: 'OK', 
    message: 'Auto-Attend Backend Simplified',
    version: '2.0-new-flow' 
  });
});

// Start Server
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
  console.log(`📡 Realtime enabled via Supabase`);
});