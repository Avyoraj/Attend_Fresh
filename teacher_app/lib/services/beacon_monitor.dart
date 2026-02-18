import 'dart:async';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

/// 📡 Beacon Monitor Service
/// Watches for ESP32 beacon rotation and notifies when Minor ID changes
class BeaconMonitor {
  // Configuration
  final String targetBeaconUUID = "1a7f44b2-e25c-44a8-a634-3d0b98065d21";
  
  // State
  int? _lastDetectedMinor;
  Timer? _scanTimer;
  bool _isMonitoring = false;
  
  // Callback for rotation detection
  Function(int newMinor)? onBeaconRotation;

  /// 🚀 Start Continuous Beacon Monitoring
  /// Scans every 30 seconds to detect Minor ID changes
  Future<void> startMonitoring({
    required Function(int newMinor) onRotation,
    Duration scanInterval = const Duration(seconds: 30),
  }) async {
    if (_isMonitoring) return;
    
    _isMonitoring = true;
    onBeaconRotation = onRotation;
    
    print("📡 Starting beacon monitoring...");

    // Initial scan
    await _performScan();

    // Periodic scanning
    _scanTimer = Timer.periodic(scanInterval, (_) async {
      await _performScan();
    });
  }

  /// 🛑 Stop Monitoring
  void stopMonitoring() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isMonitoring = false;
    _lastDetectedMinor = null;
    FlutterBluePlus.stopScan();
    print("⏹️ Beacon monitoring stopped");
  }

  /// 🔍 Perform a Single Scan
  Future<void> _performScan() async {
    try {
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final beaconData = _parseIBeacon(r.advertisementData.manufacturerData);
          
          if (beaconData != null && 
              beaconData['uuid']?.toLowerCase() == targetBeaconUUID.toLowerCase()) {
            
            final minor = beaconData['minor'] as int;
            
            // Check if Minor ID has changed (rotation detected!)
            if (_lastDetectedMinor != null && _lastDetectedMinor != minor) {
              print("🔄 Beacon rotation detected! Minor: $_lastDetectedMinor → $minor");
              onBeaconRotation?.call(minor);
            }
            
            _lastDetectedMinor = minor;
          }
        }
      });

      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 5),
      );

    } catch (e) {
      print("❌ Scan error: $e");
    }
  }

  /// 🔍 Parse iBeacon from Manufacturer Data
  Map<String, dynamic>? _parseIBeacon(Map<int, List<int>> manufacturerData) {
    // Apple Company ID is 0x004C (76 in decimal)
    final appleData = manufacturerData[76];
    if (appleData == null || appleData.length < 23) return null;

    // iBeacon format: 02 15 [UUID 16 bytes] [Major 2 bytes] [Minor 2 bytes] [TX Power 1 byte]
    if (appleData[0] != 0x02 || appleData[1] != 0x15) return null;

    // Extract UUID (bytes 2-17)
    final uuidBytes = appleData.sublist(2, 18);
    final uuid = uuidBytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join()
        .replaceAllMapped(
          RegExp(r'(.{8})(.{4})(.{4})(.{4})(.{12})'),
          (m) => '${m[1]}-${m[2]}-${m[3]}-${m[4]}-${m[5]}',
        );

    // Extract Major (bytes 18-19)
    final major = (appleData[18] << 8) + appleData[19];

    // Extract Minor (bytes 20-21)
    final minor = (appleData[20] << 8) + appleData[21];

    return {
      'uuid': uuid,
      'major': major,
      'minor': minor,
    };
  }

  /// 📊 Get Current Minor ID
  int? get currentMinor => _lastDetectedMinor;
  
  /// 🔄 Is Currently Monitoring
  bool get isMonitoring => _isMonitoring;

  /// 🧹 Cleanup
  void dispose() {
    stopMonitoring();
  }
}
