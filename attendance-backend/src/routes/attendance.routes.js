const express = require('express');
const router = express.Router();
const attendanceController = require('../controllers/attendance.controller');

// Student (Joiner) Endpoints
router.post('/check-in', attendanceController.checkIn);
router.post('/stream-rssi', attendanceController.uploadRssiStream);

// Verification Endpoint (Final Lock)
router.post('/finalize', attendanceController.finalizeVerification);

module.exports = router;