import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter_beacon/flutter_beacon.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:http/http.dart' as http;
import 'package:local_auth/local_auth.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Tracks verification pipeline stage to prevent re-entry / competing scans.
enum VerificationStage {
  idle,            // Not in any verification flow
  checkingIn,      // Beacon found → check-in request in progress
  waitingStep2,    // Check-in done → waiting for beacon rotation
  spotChecks,      // Step-2 passed → spot checks running
  biometric,       // Biometric fallback in progress
  done,            // Fully confirmed or terminal error
}

class AttendanceService {
  // Configuration
  static const _backendIp =
      String.fromEnvironment('BACKEND_IP', defaultValue: '192.168.1.117');
  final String baseUrl = "http://$_backendIp:5000/api";
  final String salt = "my_secret_salt";
  // ESP32 broadcasts UUID in reversed byte order (hardware quirk)
  final String targetBeaconUUID = "215d0698-0b3d-34a6-a844-5ce2b2447f1a";

  // State
  String? _currentSessionId;
  String? _currentClassId;
  String? _deviceId;

  // ── Verification pipeline state ──
  // Tracks where we are in the check-in → step-2 → spot-checks pipeline.
  // Prevents duplicate scans and re-entry.
  VerificationStage _stage = VerificationStage.idle;
  bool get isVerificationActive => _stage != VerificationStage.idle;
  VerificationStage get stage => _stage;

  // Beacon ranging subscription (flutter_beacon)
  StreamSubscription<RangingResult>? _rangingSubscription;
  bool _isScanInProgress = false;

  // Step-2 verification state
  int? _checkInMinor; // Minor used at initial check-in
  Timer? _step2Timer;
  final LocalAuthentication _localAuth = LocalAuthentication();

  // 5-Minute Gold Window: spot check state
  final List<Timer> _spotCheckTimers = [];
  int _spotChecksDone = 0;
  static const int _totalSpotChecks = 3;
  // Spot check schedule (seconds after step-2 confirms)
  static const List<int> _spotCheckDelays = [60, 150, 240];

  // Auth-driven student info
  String? _studentId;

  /// Load student_id from Supabase based on current auth user
  Future<String?> _getStudentId() async {
    if (_studentId != null) return _studentId;
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) return null;
      final profile = await Supabase.instance.client
          .from('students')
          .select('student_id')
          .eq('email', user.email!)
          .maybeSingle();
      if (profile != null) {
        _studentId = profile['student_id'] as String;
      }
    } catch (_) {}
    return _studentId;
  }

  /// Generate HMAC-SHA256 Signature
  String _generateSignature(String deviceId) {
    var key = utf8.encode(salt);
    var bytes = utf8.encode(deviceId);
    var hmacSha256 = Hmac(sha256, key);
    return hmacSha256.convert(bytes).toString();
  }

  /// Get Device ID
  Future<String> _getDeviceId() async {
    if (_deviceId != null) return _deviceId!;
    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      _deviceId = androidInfo.id;
    } catch (e) {
      _deviceId = "DEVICE_${DateTime.now().millisecondsSinceEpoch}";
    }
    return _deviceId!;
  }

  /// Discover Active Session from backend by beacon minor
  Future<Map<String, String>?> _discoverSession(int minor) async {
    try {
      final response = await http.get(
        Uri.parse("$baseUrl/sessions/discover?minor=$minor"),
        headers: {"Content-Type": "application/json"},
      );
      if (response.statusCode == 200) {
        final body = jsonDecode(response.body);
        return {
          'sessionId': body['sessionId'] as String,
          'classId': body['classId'] as String,
          'className': body['className'] as String? ?? '',
        };
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Start Frictionless Check-In using native iBeacon ranging API
  /// Uses flutter_beacon which leverages Android Beacon Library under the hood
  /// This works on Xiaomi/MIUI devices where raw BLE scanning filters out iBeacons
  ///
  /// Returns immediately if a verification pipeline is already running.
  Future<void> startFrictionlessCheckIn({
    Function(int minor, int rssi)? onBeaconFound,
    Function()? onCheckInSuccess,
    Function(String error)? onCheckInError,
    Function()? onNoSession,
    Function()? onStep2Waiting,
    Function()? onStep2Confirmed,
    Function()? onBiometricPrompt,
    Function()? onBiometricConfirmed,
  }) async {
    // ── Guard: don't start a new scan if verification is already running ──
    if (isVerificationActive) {
      print('[AttendanceService] Scan blocked — verification in progress (stage=$_stage)');
      return;
    }
    try {
      // ── Explicitly request runtime permissions (Android 12+ needs BLUETOOTH_SCAN) ──
      if (Platform.isAndroid) {
        final statuses = await [
          Permission.bluetoothScan,
          Permission.bluetoothConnect,
          Permission.locationWhenInUse,
          Permission.notification,        // request early so foreground service doesn't prompt later
        ].request();

        print('[AttendanceService] Permission statuses: $statuses');

        if (statuses[Permission.bluetoothScan]?.isDenied == true ||
            statuses[Permission.bluetoothScan]?.isPermanentlyDenied == true) {
          onCheckInError?.call(
              'Bluetooth Scan permission is required. Please grant it in Settings.');
          return;
        }
        if (statuses[Permission.locationWhenInUse]?.isDenied == true ||
            statuses[Permission.locationWhenInUse]?.isPermanentlyDenied == true) {
          onCheckInError?.call(
              'Location permission is required for beacon detection. Please enable it in Settings.');
          return;
        }
      }

      // Initialize beacon scanning (after permissions are granted)
      try {
        await flutterBeacon.initializeAndCheckScanning;
        print('[AttendanceService] Beacon scanning initialized');
      } catch (e) {
        print('[AttendanceService] Beacon init error: $e');
        onCheckInError?.call(
            "Bluetooth & Location must be enabled for attendance check-in. "
            "Please enable them in Settings. Error: $e");
        return;
      }

      // Cancel any previous ranging
      await _rangingSubscription?.cancel();
      _rangingSubscription = null;

      // Define region to scan — use UUID filter for targeted detection
      final regions = <Region>[
        Region(
          identifier: 'AttendFresh',
          proximityUUID: targetBeaconUUID,
        ),
      ];

      print('[AttendanceService] Starting iBeacon ranging for UUID: $targetBeaconUUID');

      bool beaconHandled = false;
      int scanDurationSeconds = 10;

      // Start native iBeacon ranging
      _rangingSubscription = flutterBeacon.ranging(regions).listen(
        (RangingResult result) async {
          if (beaconHandled) return;

          final beacons = result.beacons;
          print('[AttendanceService] Ranging result: ${beacons.length} beacon(s) found');

          for (final beacon in beacons) {
            print('[AttendanceService] Beacon: uuid=${beacon.proximityUUID} '
                'major=${beacon.major} minor=${beacon.minor} '
                'rssi=${beacon.rssi} accuracy=${beacon.accuracy}m '
                'proximity=${beacon.proximity}');

            // Match our target UUID
            if (beacon.proximityUUID.toLowerCase() == targetBeaconUUID.toLowerCase()) {
              final minor = beacon.minor;
              final rssi = beacon.rssi;

              print('[AttendanceService] *** TARGET BEACON FOUND *** Minor: $minor RSSI: $rssi');

              beaconHandled = true;
              _stage = VerificationStage.checkingIn;
              onBeaconFound?.call(minor, rssi);

              // Stop ranging once beacon found
              await _rangingSubscription?.cancel();
              _rangingSubscription = null;

              // Attempt check-in
              await _performCheckIn(
                minor: minor,
                rssi: rssi,
                onSuccess: onCheckInSuccess,
                onError: onCheckInError,
                onNoSession: onNoSession,
                onStep2Waiting: onStep2Waiting,
                onStep2Confirmed: onStep2Confirmed,
                onBiometricPrompt: onBiometricPrompt,
                onBiometricConfirmed: onBiometricConfirmed,
              );
              return;
            }
          }
        },
        onError: (error) {
          print('[AttendanceService] Ranging error: $error');
        },
      );

      // Wait for scan duration then clean up if nothing found
      await Future.delayed(Duration(seconds: scanDurationSeconds));

      if (!beaconHandled) {
        print('[AttendanceService] Ranging complete — no target beacon found');
        await _rangingSubscription?.cancel();
        _rangingSubscription = null;
        onNoSession?.call();
      }
    } catch (e) {
      await _rangingSubscription?.cancel();
      _rangingSubscription = null;
      onCheckInError?.call("Bluetooth error: ${e.toString()}");
    }
  }

  /// Perform Check-In to Backend
  Future<void> _performCheckIn({
    required int minor,
    required int rssi,
    Function()? onSuccess,
    Function(String error)? onError,
    Function()? onNoSession,
    Function()? onStep2Waiting,
    Function()? onStep2Confirmed,
    Function()? onBiometricPrompt,
    Function()? onBiometricConfirmed,
  }) async {
    try {
      final deviceId = await _getDeviceId();
      final signature = _generateSignature(deviceId);
      final studentId = await _getStudentId();

      if (studentId == null || studentId.isEmpty) {
        _stage = VerificationStage.idle;
        onError?.call('Not logged in or student profile not found');
        return;
      }

      final sessionInfo = await _discoverSession(minor);
      if (sessionInfo == null) {
        _stage = VerificationStage.idle;
        onNoSession?.call();
        return;
      }

      _currentSessionId = sessionInfo['sessionId'];
      _currentClassId = sessionInfo['classId'];

      final response = await http.post(
        Uri.parse("$baseUrl/attendance/check-in"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "studentId": studentId,
          "classId": sessionInfo['classId'],
          "sessionId": sessionInfo['sessionId'],
          "deviceId": deviceId,
          "deviceSignature": signature,
          "reportedMinor": minor,
          "rssi": rssi,
        }),
      );

      if (response.statusCode == 201) {
        // Fresh check-in — proceed to step-2
        _checkInMinor = minor;
        onSuccess?.call();
        _startStep2Verification(
          onWaiting: onStep2Waiting,
          onConfirmed: onStep2Confirmed,
          onBiometricPrompt: onBiometricPrompt,
          onBiometricConfirmed: onBiometricConfirmed,
          onError: onError,
        );
      } else if (response.statusCode == 200) {
        // Already checked in — resume step-2 if not yet confirmed
        print('[AttendanceService] Already checked in — resuming step-2');
        _checkInMinor ??= minor; // keep original if set
        onSuccess?.call();
        _startStep2Verification(
          onWaiting: onStep2Waiting,
          onConfirmed: onStep2Confirmed,
          onBiometricPrompt: onBiometricPrompt,
          onBiometricConfirmed: onBiometricConfirmed,
          onError: onError,
        );
      } else if (response.statusCode == 403) {
        final body = jsonDecode(response.body);
        if (body['error'] == 'No active session found for this class') {
          _stage = VerificationStage.idle;
          onNoSession?.call();
        } else {
          _stage = VerificationStage.idle;
          onError?.call(
              body['message'] ?? body['error'] ?? 'Check-in rejected');
        }
      } else {
        _stage = VerificationStage.idle;
        final body = jsonDecode(response.body);
        onError?.call(body['error'] ?? 'Unknown error');
      }
    } catch (e) {
      _stage = VerificationStage.idle;
      onError?.call("Network error: ${e.toString()}");
    }
  }

  /// Start Step-2 Verification: scan for rotated beacon minor
  /// 5-minute timeout → falls back to biometric
  void _startStep2Verification({
    Function()? onWaiting,
    Function()? onConfirmed,
    Function()? onBiometricPrompt,
    Function()? onBiometricConfirmed,
    Function(String)? onError,
  }) {
    _stage = VerificationStage.waitingStep2;
    onWaiting?.call();
    print('[AttendanceService] Step-2: waiting for beacon rotation...');

    // Cancel any lingering step-2 timer from a previous attempt
    _step2Timer?.cancel();

    // 5-minute timeout → biometric fallback
    _step2Timer = Timer(const Duration(minutes: 5), () {
      _rangingSubscription?.cancel();
      _rangingSubscription = null;
      _attemptBiometricFallback(
        onPrompt: onBiometricPrompt,
        onConfirmed: onBiometricConfirmed,
        onError: onError,
      );
    });

    // Scan every 15s for a new minor
    _pollForNewMinor(onConfirmed: onConfirmed, onError: onError);
  }

  /// Poll beacon for rotated minor and POST to verify-step2
  Future<void> _pollForNewMinor({
    Function()? onConfirmed,
    Function(String)? onError,
  }) async {
    final regions = <Region>[
      Region(identifier: 'AttendFreshStep2', proximityUUID: targetBeaconUUID),
    ];

    Future<void> doScan() async {
      if (_step2Timer == null) return; // timer cancelled = step-2 done
      if (_stage != VerificationStage.waitingStep2) return; // stage moved on
      await _rangingSubscription?.cancel();

      bool found = false;
      _rangingSubscription = flutterBeacon.ranging(regions).listen((result) async {
        if (found) return;
        for (final b in result.beacons) {
          if (b.proximityUUID.toLowerCase() != targetBeaconUUID.toLowerCase()) continue;
          if (b.minor != _checkInMinor) {
            // Found a different minor → try to verify it
            print('[AttendanceService] Step-2: new minor ${b.minor} (was $_checkInMinor)');
            found = true; // pause scanning while we verify
            await _rangingSubscription?.cancel();
            _rangingSubscription = null;

            // POST verify-step2
            try {
              final studentId = await _getStudentId();
              final resp = await http.post(
                Uri.parse("$baseUrl/attendance/verify-step2"),
                headers: {"Content-Type": "application/json"},
                body: jsonEncode({
                  "studentId": studentId,
                  "sessionId": _currentSessionId,
                  "reportedMinor": b.minor,
                }),
              );
              if (resp.statusCode == 200) {
                print('[AttendanceService] ✅ Step-2 confirmed (minor ${b.minor})');
                _step2Timer?.cancel();
                _step2Timer = null;
                onConfirmed?.call();
              } else {
                final body = jsonDecode(resp.body);
                print('[AttendanceService] ⚠️ Step-2 verify failed: ${body['error']}');
                if (body['message'] == 'Already confirmed') {
                  _step2Timer?.cancel();
                  _step2Timer = null;
                  onConfirmed?.call();
                } else {
                  // Verify failed — resume polling (minor may rotate again)
                  found = false;
                  doScan();
                }
              }
            } catch (e) {
              print('[AttendanceService] Step-2 network error: $e');
              // Resume polling
              found = false;
              doScan();
            }
            return;
          }
        }
      });

      // Range for 5s then pause 10s before next attempt
      await Future.delayed(const Duration(seconds: 5));
      if (!found) {
        await _rangingSubscription?.cancel();
        _rangingSubscription = null;
        await Future.delayed(const Duration(seconds: 10));
        doScan(); // recurse
      }
    }

    doScan();
  }

  /// Biometric fallback when step-2 times out
  Future<void> _attemptBiometricFallback({
    Function()? onPrompt,
    Function()? onConfirmed,
    Function(String)? onError,
  }) async {
    _stage = VerificationStage.biometric;
    onPrompt?.call();
    print('[AttendanceService] Step-2 timeout → biometric fallback');
    try {
      final didAuth = await _localAuth.authenticate(
        localizedReason: 'Verify your identity to confirm attendance',
        options: const AuthenticationOptions(biometricOnly: true),
      );
      if (!didAuth) {
        _stage = VerificationStage.idle;
        onError?.call('Biometric verification cancelled');
        return;
      }
      final studentId = await _getStudentId();
      final deviceId = await _getDeviceId();
      final resp = await http.post(
        Uri.parse("$baseUrl/attendance/biometric-confirm"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "studentId": studentId,
          "sessionId": _currentSessionId,
          "deviceId": deviceId,
        }),
      );
      if (resp.statusCode == 200) {
        print('[AttendanceService] 🔐 Biometric confirmed');
        _stage = VerificationStage.done;
        onConfirmed?.call();
      } else {
        _stage = VerificationStage.idle;
        final body = jsonDecode(resp.body);
        onError?.call(body['error'] ?? 'Biometric confirm failed');
      }
    } catch (e) {
      _stage = VerificationStage.idle;
      onError?.call('Biometric error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  //  5-MINUTE GOLD WINDOW: Spot Checks + Motion Detection
  // ═══════════════════════════════════════════════════════

  /// Start spot checks after step-2 confirms.
  /// 3 checks at ~1m, 2.5m, 4m → each sends RSSI + motion flag.
  /// After all 3, ask backend to analyze → confirmed or flagged.
  /// If flagged/inconclusive → biometric fallback.
  void startSpotChecks({
    Function()? onSpotCheckActive,
    Function()? onAllClear,
    Function()? onFlagged,
    Function()? onBiometricPrompt,
    Function()? onBiometricConfirmed,
    Function(String)? onError,
  }) {
    _stage = VerificationStage.spotChecks;
    _spotChecksDone = 0;
    onSpotCheckActive?.call();
    print('[AttendanceService] 🎯 Starting 5-min Gold Window (${_spotCheckDelays.length} spot checks)');

    // Start foreground service to prevent Android from killing the app
    _startForegroundService();

    for (int i = 0; i < _spotCheckDelays.length; i++) {
      final t = Timer(Duration(seconds: _spotCheckDelays[i]), () async {
        await _doSpotCheck(i + 1);
        _spotChecksDone++;

        if (_spotChecksDone >= _totalSpotChecks) {
          print('[AttendanceService] 📊 All spot checks done — requesting analysis');
          await _requestAnalysis(
            onAllClear: onAllClear,
            onFlagged: onFlagged,
            onBiometricPrompt: onBiometricPrompt,
            onBiometricConfirmed: onBiometricConfirmed,
            onError: onError,
          );
        }
      });
      _spotCheckTimers.add(t);
    }
  }

  /// Single spot check: 3s beacon scan + 2s accelerometer read → POST to backend
  Future<void> _doSpotCheck(int checkNum) async {
    if (_isScanInProgress) return;
    _isScanInProgress = true;
    print('[AttendanceService] 📡 Spot check #$checkNum starting...');

    try {
      List<Map<String, dynamic>> rssiReadings = [];

      // 1) Beacon scan for 3s
      await _rangingSubscription?.cancel();
      final regions = <Region>[
        Region(identifier: 'AttendFreshSpot', proximityUUID: targetBeaconUUID),
      ];

      _rangingSubscription = flutterBeacon.ranging(regions).listen((result) {
        for (final b in result.beacons) {
          if (b.proximityUUID.toLowerCase() == targetBeaconUUID.toLowerCase()) {
            rssiReadings.add({
              "rssi": b.rssi,
              "minor": b.minor,
              "timestamp": DateTime.now().toIso8601String(),
            });
          }
        }
      });
      await Future.delayed(const Duration(seconds: 3));
      await _rangingSubscription?.cancel();
      _rangingSubscription = null;

      // 2) Accelerometer motion check (2s)
      final hasMotion = await _detectRecentMotion();

      // 3) Send to backend
      if (rssiReadings.isNotEmpty) {
        // Add motion flag to each reading
        for (final r in rssiReadings) {
          r['hasMotion'] = hasMotion;
        }
        await _sendRssiStream(rssiReadings);
        print('[AttendanceService] ✅ Spot check #$checkNum sent '
            '(${rssiReadings.length} readings, motion=$hasMotion)');
      } else {
        // No beacon found — send a "missed" marker
        await _sendRssiStream([{
          "rssi": 0,
          "minor": 0,
          "timestamp": DateTime.now().toIso8601String(),
          "hasMotion": hasMotion,
          "missed": true,
        }]);
        print('[AttendanceService] ⚠️ Spot check #$checkNum: no beacon found');
      }
    } catch (e) {
      print('[AttendanceService] Spot check error: $e');
    } finally {
      _isScanInProgress = false;
    }
  }

  /// 2-second accelerometer snapshot → true if phone was moved/held
  /// Uses `userAccelerometerEventStream` which automatically removes gravity.
  /// On a perfectly still phone every axis reads ~0. Any real movement shows up
  /// as non-zero values. We compute the RMS of the gravity-free acceleration
  /// and declare motion when it exceeds a low threshold.
  Future<bool> _detectRecentMotion() async {
    double sumSquared = 0;
    int sampleCount = 0;
    late StreamSubscription sub;
    sub = userAccelerometerEventStream().listen((event) {
      // event.x/y/z already have gravity removed (linear acceleration)
      sumSquared += event.x * event.x + event.y * event.y + event.z * event.z;
      sampleCount++;
    });
    await Future.delayed(const Duration(seconds: 2));
    await sub.cancel();

    if (sampleCount == 0) return false;

    // RMS of linear acceleration — phone on desk ≈ 0.0-0.3, hand-held ≈ 0.5-3+
    final rms = (sumSquared / sampleCount);
    // rms is variance (mean of squared accel); sqrt would give m/s².
    // Threshold: 0.15 m/s² squared → ~0.39 m/s² RMS — slight hand tremor passes.
    final moved = rms > 0.15;
    print('[AttendanceService] 🏃 Motion detection: rms=$rms samples=$sampleCount moved=$moved');
    return moved;
  }

  /// Ask backend to analyze spot check data and return verdict
  Future<void> _requestAnalysis({
    Function()? onAllClear,
    Function()? onFlagged,
    Function()? onBiometricPrompt,
    Function()? onBiometricConfirmed,
    Function(String)? onError,
  }) async {
    try {
      final studentId = await _getStudentId();
      final resp = await http.post(
        Uri.parse("$baseUrl/attendance/analyze"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "studentId": studentId,
          "sessionId": _currentSessionId,
          "classId": _currentClassId,
        }),
      );

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        final status = body['status'] as String? ?? '';
        print('[AttendanceService] 📊 Analysis result: $status');

        if (status == 'confirmed') {
          _stage = VerificationStage.done;
          onAllClear?.call();
          _stopSpotChecks();
        } else {
          // flagged or inconclusive → biometric as last resort
          onFlagged?.call();
          _stopSpotChecks();
          await _attemptBiometricFallback(
            onPrompt: onBiometricPrompt,
            onConfirmed: onBiometricConfirmed,
            onError: onError,
          );
        }
      } else {
        // Backend error → biometric safety net
        print('[AttendanceService] ⚠️ Analysis request failed, falling back to biometric');
        _stopSpotChecks();
        await _attemptBiometricFallback(
          onPrompt: onBiometricPrompt,
          onConfirmed: onBiometricConfirmed,
          onError: onError,
        );
      }
    } catch (e) {
      print('[AttendanceService] Analysis error: $e');
      _stopSpotChecks();
      await _attemptBiometricFallback(
        onPrompt: onBiometricPrompt,
        onConfirmed: onBiometricConfirmed,
        onError: onError,
      );
    }
  }

  /// Send RSSI + motion data to backend
  Future<void> _sendRssiStream(List<Map<String, dynamic>> rssiData) async {
    try {
      final studentId = await _getStudentId();
      final response = await http.post(
        Uri.parse("$baseUrl/attendance/stream-rssi"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "studentId": studentId ?? "UNKNOWN",
          "classId": _currentClassId ?? "",
          "rssiData": rssiData,
        }),
      );
      if (response.statusCode == 200) {
        print("[AttendanceService] RSSI stream sent: ${rssiData.length} readings");
      }
    } catch (e) {
      print("[AttendanceService] RSSI stream error: $e");
    }
  }

  /// Stop all spot check timers and foreground service
  void _stopSpotChecks() {
    for (final t in _spotCheckTimers) {
      t.cancel();
    }
    _spotCheckTimers.clear();
    _stopForegroundService();
    print("[AttendanceService] Spot checks stopped");
  }

  // ════════════════════════════════════════
  //  Foreground Service (keeps app alive)
  // ════════════════════════════════════════

  /// Start a lightweight foreground service notification so Android
  /// doesn't kill the app during the ~5-min spot check window.
  Future<void> _startForegroundService() async {
    // On Android 13+ we need POST_NOTIFICATIONS permission for the notification
    if (Platform.isAndroid) {
      final notifStatus = await Permission.notification.request();
      print('[AttendanceService] Notification permission: $notifStatus');
    }

    final result = await FlutterForegroundTask.startService(
      notificationTitle: 'Attendance Verification',
      notificationText: 'Confirming your presence — stay in class',
    );
    print('[AttendanceService] Foreground service started: $result');
  }

  /// Stop the foreground service once spot checks are done.
  Future<void> _stopForegroundService() async {
    final result = await FlutterForegroundTask.stopService();
    print('[AttendanceService] Foreground service stopped: $result');
  }

  /// Cleanup
  void dispose() {
    _stopSpotChecks();
    _step2Timer?.cancel();
    _step2Timer = null;
    _rangingSubscription?.cancel();
    _rangingSubscription = null;
    _stage = VerificationStage.idle;
  }
}
