const express = require('express');
const router = express.Router();
const anomalyController = require('../controllers/anomaly.controller');

router.get('/pending', anomalyController.getPendingAnomalies);

module.exports = router;