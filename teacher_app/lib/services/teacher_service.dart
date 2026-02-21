import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// 🎓 Teacher Service
/// Handles session management, beacon sync, and attendance monitoring
class TeacherService {
  // Configuration — pass via: flutter run --dart-define=BACKEND_IP=x.x.x.x
  static const _backendIp = String.fromEnvironment('BACKEND_IP', defaultValue: '192.168.1.117');
  final String baseUrl = "http://$_backendIp:5000/api";
  final SupabaseClient supabase = Supabase.instance.client;

  // Current session state
  String? _currentSessionId;
  String? get currentSessionId => _currentSessionId;

  /// 🚀 Start a New Class Session
  /// Creates an active session in the backend
  Future<Map<String, dynamic>?> startSession({
    required String classId,
    required String className,
    required String roomId,
    required String teacherId,
    required String teacherName,
    int beaconMajor = 1,
    int beaconMinor = 101,
  }) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/sessions/start"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "roomId": roomId,
          "classId": classId,
          "className": className,
          "teacherId": teacherId,
          "teacherName": teacherName,
          "beaconMajor": beaconMajor,
          "beaconMinor": beaconMinor,
        }),
      );

      if (response.statusCode == 201) {
        final data = jsonDecode(response.body);
        _currentSessionId = data['session']['id'];
        print("🚀 Session started: $_currentSessionId");
        return data['session'];
      } else if (response.statusCode == 409) {
        print("⚠️ Session already active in this room");
        return null;
      } else {
        print("❌ Failed to start session: ${response.body}");
        return null;
      }
    } catch (e) {
      print("❌ Network error: $e");
      return null;
    }
  }

  /// 🏁 End Current Session
  /// Marks the session as ended
  Future<bool> endSession(String sessionId) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/sessions/$sessionId/end"),
        headers: {"Content-Type": "application/json"},
      );

      if (response.statusCode == 200) {
        print("✅ Session ended: $sessionId");
        _currentSessionId = null;
        return true;
      } else {
        print("❌ Failed to end session: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Network error: $e");
      return false;
    }
  }

  /// 💓 Sync Beacon Minor ID (Heartbeat)
  /// Call this when ESP32 rotates its Minor ID
  Future<bool> syncBeaconRotation(String sessionId, int newMinor) async {
    try {
      final response = await http.patch(
        Uri.parse("$baseUrl/sessions/sync-minor"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "sessionId": sessionId,
          "newMinorId": newMinor,
        }),
      );

      if (response.statusCode == 200) {
        print("🔄 Synced Beacon Minor: $newMinor");
        return true;
      } else {
        print("❌ Sync failed: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Network error: $e");
      return false;
    }
  }

  /// Fetch attendance records for a session (polling-based, no Realtime needed)
  Future<List<Map<String, dynamic>>> fetchAttendance(String sessionId) async {
    try {
      final response = await supabase
          .from('attendance')
          .select('*')
          .eq('session_id', sessionId)
          .order('check_in_time', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('[TeacherService] fetchAttendance error: $e');
      return [];
    }
  }

  /// 📊 Get Session Statistics
  Future<Map<String, int>> getSessionStats(String sessionId) async {
    try {
      final response = await supabase
          .from('attendance')
          .select('status')
          .eq('session_id', sessionId);

      int total = response.length;
      int confirmed = response.where((r) => r['status'] == 'confirmed').length;
      int provisional = response.where((r) => r['status'] == 'provisional').length;
      int step2Verified = response.where((r) => r['status'] == 'step2_verified').length;
      int flagged = response.where((r) => r['status'] == 'flagged').length;

      return {
        'total': total,
        'confirmed': confirmed,
        'provisional': provisional,
        'step2_verified': step2Verified,
        'flagged': flagged,
      };
    } catch (e) {
      print("❌ Error fetching stats: $e");
      return {'total': 0, 'confirmed': 0, 'provisional': 0, 'step2_verified': 0, 'flagged': 0};
    }
  }

  /// ✅ Manually Confirm Student Attendance
  /// Used for physical verification of flagged students
  Future<bool> confirmAttendance(String attendanceId, String teacherId) async {
    try {
      await supabase.from('attendance').update({
        'status': 'confirmed',
        'confirmed_at': DateTime.now().toIso8601String(),
        'physical_verified_by': teacherId,
      }).eq('id', attendanceId);

      print("✅ Attendance confirmed: $attendanceId");
      return true;
    } catch (e) {
      print("❌ Confirmation error: $e");
      return false;
    }
  }

  /// ❌ Mark Student as Absent (Proxy Detected)
  Future<bool> markAsAbsent(String attendanceId, String reason) async {
    try {
      await supabase.from('attendance').update({
        'status': 'absent',
        'cancelled_at': DateTime.now().toIso8601String(),
        'cancellation_reason': reason,
      }).eq('id', attendanceId);

      print("❌ Marked as absent: $attendanceId");
      return true;
    } catch (e) {
      print("❌ Error: $e");
      return false;
    }
  }

  /// 📋 Get Today's Classes for Teacher
  Future<List<Map<String, dynamic>>> getTodayClasses(String teacherId) async {
    try {
      final response = await supabase
          .from('classes')
          .select('*')
          .eq('teacher_id', teacherId)
          .eq('is_active', true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("❌ Error fetching classes: $e");
      return [];
    }
  }

  /// 🏠 Get Available Rooms
  Future<List<Map<String, dynamic>>> getAvailableRooms() async {
    try {
      final response = await supabase
          .from('rooms')
          .select('*')
          .eq('is_active', true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print("❌ Error fetching rooms: $e");
      return [];
    }
  }

  /// 🔓 Reset Student Device Binding
  /// Allows student to check in from a new phone
  Future<bool> resetStudentDevice(String studentId) async {
    try {
      final response = await http.post(
        Uri.parse("$baseUrl/attendance/reset-device"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"studentId": studentId}),
      );
      if (response.statusCode == 200) {
        print("🔓 Device reset: $studentId");
        return true;
      } else {
        print("❌ Device reset failed: ${response.body}");
        return false;
      }
    } catch (e) {
      print("❌ Network error: $e");
      return false;
    }
  }
}
