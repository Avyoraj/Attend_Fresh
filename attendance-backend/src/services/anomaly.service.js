// src/services/anomaly.service.js
const { supabaseAdmin } = require('../utils/supabase');
const correlationService = require('./correlation.service');

class AnomalyService {
  /**
   * 🔍 Analyze Risk Between Two RSSI Streams
   * Uses correlation + behavioral features to detect proxy attendance.
   */
  analyzeRisk(streamA, streamB) {
    const pearson = correlationService.computePearsonCorrelation(streamA, streamB);
    
    // 1. Feature: Signal Jitter (Δ RSSI)
    // High jitter = In pocket/hand. Zero jitter = Left on desk.
    const jitterA = this.calculateJitter(streamA);
    const jitterB = this.calculateJitter(streamB);

    // 2. Feature: Frequency Check
    // Ghost phones often have lower ping frequency due to OS power saving.
    const freqA = streamA.length; 
    const freqB = streamB.length;

    // 🎯 Risk Scorer (The "Behavioral" Layer)
    let riskScore = 0;
    if (pearson > 0.85) riskScore += 50; // High Correlation
    if (Math.abs(jitterA - jitterB) < 0.5) riskScore += 30; // Identical movement patterns
    if (freqA === freqB) riskScore += 20; // Identical ping timing (very suspicious)

    return {
      score: riskScore,
      isFlagged: riskScore >= 70, // 🚩 Threshold for Layer 3 Physical Check
      pearson
    };
  }

  /**
   * 📊 Calculate Signal Jitter
   * Measures variation in RSSI readings over time.
   */
  calculateJitter(data) {
    if (data.length < 2) return 0;
    const diffs = data.slice(1).map((d, i) => Math.abs(d.rssi - data[i].rssi));
    return diffs.reduce((a, b) => a + b, 0) / diffs.length;
  }

  /**
   * 🚨 Log Proxy Anomaly
   * Persists a suspicious pattern between two students.
   */
  async createAnomaly({ student1, student2, classId, sessionDate, score }) {
    const { data, error } = await supabaseAdmin
      .from('anomalies')
      .insert({
        student_id_1: student1,
        student_id_2: student2,
        class_id: classId,
        session_date: sessionDate,
        correlation_score: score,
        status: 'pending'
      });

    if (error) console.error('❌ Error logging anomaly:', error);
    return data;
  }
}

module.exports = new AnomalyService();