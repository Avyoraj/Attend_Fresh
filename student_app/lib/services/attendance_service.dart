import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AttendanceService {
  // Configuration — pass via: flutter run --dart-define=BACKEND_IP=x.x.x.x
  static const _backendIp = String.fromEnvironment('BACKEND_IP', defaultValue: '192.168.1.117');
  final String baseUrl = "http://$_backendIp:5000/api";
  final String salt = "my_secret_salt"; // Must match backend .env DEVICE_SALT_SECRET
  final String targetBeaconUUID = "215d0698-0b3d-34a6-a844-5ce2b2447f1a";
  
  // State
  Timer? _rssiStreamTimer;
  bool _isStreaming = false;
  String? _currentSessionId;
  String? _deviceId;

  /// 🛡️ Generate HMAC-SHA256 Signature
  /// Matches the logic in your backend security.js
  String _generateSignature(String deviceId) {
    var key = utf8.encode(salt);
    var bytes = utf8.encode(deviceId);
    var hmacSha256 = Hmac(sha256, key);
    return hmacSha256.convert(bytes).toString();
  }

  /// � Get Device ID
  Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      _deviceId = androidInfo.id;
    } catch (e) {
      // Fallback for iOS or other platforms
      _deviceId = "DEVICE_${DateTime.now().millisecondsSinceEpoch}";
    }
    return _deviceId!;
  }

  /// 🔧 Check if New Pipeline is Enabled
  Future<bool> _isNewPipelineEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('new_pipeline_enabled') ?? false;
  }

  /// 📡 Start Frictionless Check-In with Callbacks
  Future<void> startFrictionlessCheckIn({
    Function(int minor, int rssi)? onBeaconFound,
    Function()? onCheckInSuccess,
    Function(String error)? onCheckInError,
    Function()? onNoSession,
  }) async {
    try {
      // Check Bluetooth status
      if (await FlutterBluePlus.isAvailable == false) {
        onCheckInError?.call("Bluetooth not supported or not available on this device");
        return;
      }

      // Start scanning
      FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          // Look for iBeacon with our UUID in manufacturer data
          final manufacturerData = r.advertisementData.manufacturerData;
          
          if (manufacturerData.isNotEmpty) {
            // Parse iBeacon data (Apple Company ID: 0x004C)
            final beaconData = _parseIBeacon(manufacturerData);
            
            if (beaconData != null && 
                beaconData['uuid']?.toLowerCase() == targetBeaconUUID.toLowerCase()) {
              
              final minor = beaconData['minor'] as int;
              final rssi = r.rssi;
              
              onBeaconFound?.call(minor, rssi);
              
              // Stop scanning once beacon found
              await FlutterBluePlus.stopScan();
              
              // Attempt check-in
              await _performCheckIn(
                minor: minor,
                rssi: rssi,
                onSuccess: onCheckInSuccess,
                onError: onCheckInError,
                onNoSession: onNoSession,
              );
              
              return;
            }
          }
        }
      });

      // Start the scan
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 10),
      );

      // If scan completes without finding beacon
      await Future.delayed(const Duration(seconds: 11));
      if (!_isStreaming) {
        onNoSession?.call();
      }

    } catch (e) {
      onCheckInError?.call("Bluetooth error: ${e.toString()}");
    }
  }

  /// 📥 Perform Check-In to Backend
  Future<void> _performCheckIn({
    required int minor,
    required int rssi,
    Function()? onSuccess,
    Function(String error)? onError,
    Function()? onNoSession,
  }) async {
    try {
      final deviceId = await _getDeviceId();
      final signature = _generateSignature(deviceId);
      final isNewPipeline = await _isNewPipelineEnabled();

      final response = await http.post(
        Uri.parse("$baseUrl/attendance/check-in"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "studentId": "STU_0080", // TODO: Get from auth
          "classId": "CS101",      // TODO: Get from active session lookup
          "sessionId": _currentSessionId ?? "YOUR_SESSION_UUID", // TODO: Fetch active session
          "deviceId": deviceId,
          "deviceSignature": signature,
          "reportedMinor": minor,
          "rssi": rssi,
        }),
      );

      if (response.statusCode == 201) {
        onSuccess?.call();
        
        // If new pipeline is enabled, start RSSI streaming
        if (isNewPipeline) {
          _startRssiStreaming(minor);
        }
      } else if (response.statusCode == 403) {
        final body = jsonDecode(response.body);
        if (body['error'] == 'No active session found for this class') {
          onNoSession?.call();
        } else {
          onError?.call(body['message'] ?? body['error'] ?? 'Check-in rejected');
        }
      } else if (response.statusCode == 200) {
        // Already checked in
        onSuccess?.call();
      } else {
        final body = jsonDecode(response.body);
        onError?.call(body['error'] ?? 'Unknown error');
      }
    } catch (e) {
      onError?.call("Network error: ${e.toString()}");
    }
  }

  /// 📡 Start 45-minute RSSI Streaming (New Pipeline)
  void _startRssiStreaming(int beaconMinor) {
    if (_isStreaming) return;
    
    _isStreaming = true;
    print("🔄 Starting 45-minute RSSI streaming...");

    // Stream RSSI data every 30 seconds for 45 minutes
    int streamCount = 0;
    const maxStreams = 90; // 45 min * 2 per minute

    _rssiStreamTimer = Timer.periodic(const Duration(seconds: 30), (timer) async {
      streamCount++;
      
      if (streamCount >= maxStreams) {
        stopRssiStreaming();
        return;
      }

      // Quick scan for RSSI reading
      await _captureAndSendRssi();
    });
  }

  /// 📤 Capture RSSI and Send to Backend
  Future<void> _captureAndSendRssi() async {
    try {
      List<Map<String, dynamic>> rssiReadings = [];

      // Quick 2-second scan to capture current RSSI
      FlutterBluePlus.scanResults.listen((results) {
        for (ScanResult r in results) {
          final beaconData = _parseIBeacon(r.advertisementData.manufacturerData);
          if (beaconData != null && 
              beaconData['uuid']?.toLowerCase() == targetBeaconUUID.toLowerCase()) {
            rssiReadings.add({
              "rssi": r.rssi,
              "timestamp": DateTime.now().toIso8601String(),
              "minor": beaconData['minor'],
            });
          }
        }
      });

      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 2));
      await Future.delayed(const Duration(seconds: 3));

      if (rssiReadings.isNotEmpty) {
        await _sendRssiStream(rssiReadings);
      }
    } catch (e) {
      print("❌ RSSI capture error: $e");
    }
  }

  /// 📤 Send RSSI Stream to Backend
  Future<void> _sendRssiStream(List<Map<String, dynamic>> rssiData) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/attendance/stream-rssi"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "studentId": "STU_0080",
          "classId": "CS101",
          "rssiData": rssiData,
        }),
      );

      if (response.statusCode == 200) {
        print("✅ RSSI stream sent: ${rssiData.length} readings");
      }
    } catch (e) {
      print("❌ RSSI stream error: $e");
    }
  }

  /// 🛑 Stop RSSI Streaming
  void stopRssiStreaming() {
    _rssiStreamTimer?.cancel();
    _rssiStreamTimer = null;
    _isStreaming = false;
    print("⏹️ RSSI streaming stopped");
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

  /// 🧹 Cleanup
  void dispose() {
    stopRssiStreaming();
    FlutterBluePlus.stopScan();
  }
}