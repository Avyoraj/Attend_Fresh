import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:permission_handler/permission_handler.dart';

/// Beacon Monitor Service
/// Uses native iBeacon ranging API (Android Beacon Library under the hood)
/// Watches for ESP32 beacon rotation and notifies when Minor ID changes
class BeaconMonitor {
  // Configuration — ESP32 broadcasts UUID in reversed byte order (hardware quirk)
  final String targetBeaconUUID = '215d0698-0b3d-34a6-a844-5ce2b2447f1a';

  // State
  int? _lastDetectedMinor;
  Timer? _scanTimer;
  bool _isMonitoring = false;
  StreamSubscription<RangingResult>? _rangingSubscription;

  // Callback for rotation detection
  Function(int newMinor)? onBeaconRotation;

  /// Start Continuous Beacon Monitoring
  Future<void> startMonitoring({
    required Function(int newMinor) onRotation,
    Duration scanInterval = const Duration(seconds: 30),
  }) async {
    if (_isMonitoring) return;

    // ── Explicitly request runtime permissions (Android 12+ needs BLUETOOTH_SCAN) ──
    if (Platform.isAndroid) {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.locationWhenInUse,
      ].request();

      print('[BeaconMonitor] Permission statuses: $statuses');

      if (statuses[Permission.bluetoothScan]?.isDenied == true ||
          statuses[Permission.bluetoothScan]?.isPermanentlyDenied == true) {
        print('[BeaconMonitor] BLUETOOTH_SCAN permission denied — cannot scan');
        return;
      }
      if (statuses[Permission.locationWhenInUse]?.isDenied == true ||
          statuses[Permission.locationWhenInUse]?.isPermanentlyDenied == true) {
        print('[BeaconMonitor] Location permission denied — cannot scan');
        return;
      }
    }

    // Initialize beacon scanning (after permissions are granted)
    try {
      await flutterBeacon.initializeAndCheckScanning;
      print('[BeaconMonitor] Beacon scanning initialized');
    } catch (e) {
      print('[BeaconMonitor] Beacon init error: $e');
      return;
    }

    _isMonitoring = true;
    onBeaconRotation = onRotation;

    print('[BeaconMonitor] Starting...');

    await _performScan();

    _scanTimer = Timer.periodic(scanInterval, (_) async {
      await _performScan();
    });
  }

  /// Stop Monitoring
  void stopMonitoring() {
    _scanTimer?.cancel();
    _scanTimer = null;
    _isMonitoring = false;
    _lastDetectedMinor = null;
    _rangingSubscription?.cancel();
    _rangingSubscription = null;
    print('[BeaconMonitor] Stopped');
  }

  /// Perform a Single Scan using native iBeacon ranging
  Future<void> _performScan() async {
    try {
      // Cancel any previous ranging
      await _rangingSubscription?.cancel();
      _rangingSubscription = null;

      final regions = <Region>[
        Region(
          identifier: 'AttendFresh',
          proximityUUID: targetBeaconUUID,
        ),
      ];

      print('[BeaconMonitor] Starting iBeacon ranging...');

      _rangingSubscription = flutterBeacon.ranging(regions).listen(
        (RangingResult result) {
          final beacons = result.beacons;
          if (beacons.isNotEmpty) {
            print('[BeaconMonitor] Ranging: ${beacons.length} beacon(s)');
          }

          for (final beacon in beacons) {
            print('[BeaconMonitor] Beacon: uuid=${beacon.proximityUUID} '
                'major=${beacon.major} minor=${beacon.minor} '
                'rssi=${beacon.rssi} accuracy=${beacon.accuracy}m');

            if (beacon.proximityUUID.toLowerCase() == targetBeaconUUID.toLowerCase()) {
              final minor = beacon.minor;
              if (_lastDetectedMinor == null || _lastDetectedMinor != minor) {
                print('[BeaconMonitor] *** TARGET MATCH *** Minor: $minor');
                _lastDetectedMinor = minor;
                onBeaconRotation?.call(minor);
              }
            }
          }
        },
        onError: (error) {
          print('[BeaconMonitor] Ranging error: $error');
        },
      );

      // Range for 6 seconds then stop
      await Future.delayed(const Duration(seconds: 6));

      await _rangingSubscription?.cancel();
      _rangingSubscription = null;

      print('[BeaconMonitor] Scan cycle complete');
    } catch (e) {
      print('[BeaconMonitor] Scan error: $e');
      await _rangingSubscription?.cancel();
      _rangingSubscription = null;
    }
  }

  int? get currentMinor => _lastDetectedMinor;
  bool get isMonitoring => _isMonitoring;

  void dispose() {
    stopMonitoring();
  }
}
