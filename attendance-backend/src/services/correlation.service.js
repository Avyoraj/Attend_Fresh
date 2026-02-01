/**
 * 📈 Correlation Service
 * * Logic to detect proxy attendance by analyzing signal patterns 
 * between two student devices.
 */

class CorrelationService {
  /**
   * Computes the Pearson Correlation Coefficient (ρ) between two series.
   * Result ranges from -1 to +1. 
   * Near +1 means the devices are moving in perfect sync.
   */
  computePearsonCorrelation(seriesA, seriesB) {
    // Ensure we are comparing equal lengths (simplification for rewrite)
    const length = Math.min(seriesA.length, seriesB.length);
    if (length < 5) return null; // Not enough data for analysis

    const x = seriesA.slice(0, length).map(d => d.rssi);
    const y = seriesB.slice(0, length).map(d => d.rssi);

    const muX = x.reduce((a, b) => a + b, 0) / length;
    const muY = y.reduce((a, b) => a + b, 0) / length;

    let numerator = 0;
    let sumSqX = 0;
    let sumSqY = 0;

    for (let i = 0; i < length; i++) {
      const diffX = x[i] - muX;
      const diffY = y[i] - muY;
      numerator += diffX * diffY;
      sumSqX += diffX ** 2;
      sumSqY += diffY ** 2;
    }

    const denominator = Math.sqrt(sumSqX * sumSqY);
    if (denominator === 0) return 0;

    return numerator / denominator;
  }

  /**
   * Determines if a pattern is suspicious.
   * High Correlation (> 0.8) + Low Variance = Proxy Risk.
   */
  isSuspicious(correlation, varianceA, varianceB) {
    const HIGH_CORRELATION_THRESHOLD = 0.85;
    const LOW_VARIANCE_THRESHOLD = 2.0; // Static phones don't move

    const result = {
      isProxy: correlation > HIGH_CORRELATION_THRESHOLD,
      isStatic: varianceA < LOW_VARIANCE_THRESHOLD || varianceB < LOW_VARIANCE_THRESHOLD,
      score: correlation
    };

    return result;
  }
}

module.exports = new CorrelationService();