const express = require('express');
const router = express.Router();
const sessionController = require('../controllers/session.controller');

// Host endpoints
router.post('/start', sessionController.startSession);
router.post('/:sessionId/end', sessionController.endSession);

// 💓 Heartbeat: Sync Minor ID from Teacher App
router.patch('/sync-minor', sessionController.updateSessionMinor);

module.exports = router;