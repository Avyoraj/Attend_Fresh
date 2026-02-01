const anomalyService = require('../src/services/anomaly.service');

// Mock Data: Two phones moving together (Proxy)
const streamA = [{ rssi: -70 }, { rssi: -72 }, { rssi: -68 }];
const streamB = [{ rssi: -71 }, { rssi: -73 }, { rssi: -69 }];

// Mock Data: Two phones moving differently (Real Students)
const streamC = [{ rssi: -70 }, { rssi: -85 }, { rssi: -60 }];

console.log("🧪 Testing Risk Engine...");

const proxyResult = anomalyService.analyzeRisk(streamA, streamB);
console.log(`Proxy Test: Score ${proxyResult.score}, Flagged: ${proxyResult.isFlagged}`); 
// Expected: High Score (>70), Flagged: true

const realResult = anomalyService.analyzeRisk(streamA, streamC);
console.log(`Real Student Test: Score ${realResult.score}, Flagged: ${realResult.isFlagged}`);
// Expected: Low Score, Flagged: false