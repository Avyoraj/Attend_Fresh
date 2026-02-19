const express = require('express');
const router = express.Router();
const c = require('../controllers/attendance.controller');

router.post('/check-in', c.checkIn);
router.post('/stream-rssi', c.uploadRssiStream);
router.post('/finalize', c.finalizeVerification);
router.post('/verify-step2', c.verifyStep2);
router.post('/biometric-confirm', c.biometricConfirm);
router.post('/reset-device', c.resetDevice);

module.exports = router;