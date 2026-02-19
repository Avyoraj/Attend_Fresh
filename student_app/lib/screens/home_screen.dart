import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/status_card.dart';
import '../services/attendance_service.dart';

/// 🏠 Home Screen
/// Shows attendance status, beacon scanning, and weekly progress
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final AttendanceService _attendanceService = AttendanceService();
  final SupabaseClient _supabase = Supabase.instance.client;
  
  // UI State
  bool _isScanning = false;
  int _scanRetryCount = 0;
  static const int _maxScanRetries = 5;
  Timer? _retryTimer;
  String _statusTitle = "No Attendance Yet";
  String _statusSubtitle = "Move near a beacon to check in";
  IconData _statusIcon = Icons.access_time_filled;
  Color _statusColor = Colors.grey;

  // Real stats
  int _attendedClasses = 0;
  int _totalClasses = 0;
  String _studentName = '';
  String _studentId = '';
  List<Map<String, dynamic>> _todayClasses = [];

  @override
  void initState() {
    super.initState();
    _loadStudentData();
    // Auto-scan after short delay so the UI renders first
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted && !_isScanning) {
        _startScanning();
      }
    });
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _attendanceService.dispose();
    super.dispose();
  }

  Future<void> _loadStudentData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      // Get student profile
      final profile = await _supabase
          .from('students')
          .select()
          .eq('email', user.email!)
          .maybeSingle();

      if (profile != null) {
        _studentName = profile['name'] ?? 'Student';
        _studentId = profile['student_id'] ?? '';
      } else {
        _studentName = user.email?.split('@').first ?? 'Student';
      }

      // Get weekly attendance stats (this week)
      final now = DateTime.now();
      final weekStart = now.subtract(Duration(days: now.weekday - 1));
      final weekStartStr = weekStart.toIso8601String().split('T')[0];

      // Total sessions this week (across all classes)
      final sessionsThisWeek = await _supabase
          .from('sessions')
          .select('id')
          .gte('session_date', weekStartStr)
          .eq('status', 'ended');

      _totalClasses = (sessionsThisWeek as List).length;

      // Attended this week
      if (_studentId.isNotEmpty) {
        final attendedThisWeek = await _supabase
            .from('attendance')
            .select('id')
            .eq('student_id', _studentId)
            .gte('session_date', weekStartStr)
            .inFilter('status', ['confirmed', 'provisional']);

        _attendedClasses = (attendedThisWeek as List).length;

        // Today's classes with attendance status
        final todayStr = now.toIso8601String().split('T')[0];
        final todaySessions = await _supabase
            .from('sessions')
            .select('id, class_id, class_name, room_id, actual_start, status')
            .eq('session_date', todayStr)
            .order('actual_start', ascending: true);

        final todayAttendance = await _supabase
            .from('attendance')
            .select('session_id, status')
            .eq('student_id', _studentId)
            .eq('session_date', todayStr);

        final attendanceMap = <String, String>{};
        for (final a in todayAttendance as List) {
          attendanceMap[a['session_id']] = a['status'];
        }

        _todayClasses = (todaySessions as List).map((s) {
          final sessionId = s['id'] as String;
          final attStatus = attendanceMap[sessionId];
          return {
            'name': s['class_name'] ?? s['class_id'] ?? 'Unknown',
            'time': _formatTime(s['actual_start']),
            'room': s['room_id'] ?? '',
            'attended': attStatus == 'confirmed' || attStatus == 'provisional',
            'status': attStatus,
          };
        }).toList();
      }

      // Also count active sessions (include them in total if no ended ones yet)
      final activeSessions = await _supabase
          .from('sessions')
          .select('id')
          .gte('session_date', weekStartStr)
          .eq('status', 'active');
      
      _totalClasses += (activeSessions as List).length;

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading student data: $e');
    }
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return '';
    try {
      final dt = DateTime.parse(isoTime).toLocal();
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${hour.toString()}:${dt.minute.toString().padLeft(2, '0')} $amPm';
    } catch (_) {
      return '';
    }
  }

  Future<void> _startScanning() async {
    if (_scanRetryCount == 0) {
      // Only reset UI for first scan, not retries
    }
    setState(() {
      _isScanning = true;
      _statusTitle = _scanRetryCount > 0
          ? "🔍 Retry scan $_scanRetryCount/$_maxScanRetries..."
          : "🔍 Searching for classroom beacon...";
      _statusSubtitle = "Move closer to the classroom.";
      _statusIcon = Icons.track_changes;
      _statusColor = Colors.orange;
    });

    try {
      await _attendanceService.startFrictionlessCheckIn(
        onBeaconFound: (minor, rssi) {
          setState(() {
            _statusTitle = "📡 Beacon Found! (Minor: $minor)";
            _statusSubtitle = "Sending check-in request...";
            _statusIcon = Icons.bluetooth_connected;
            _statusColor = Colors.blue;
          });
        },
        onCheckInSuccess: () {
          setState(() {
            _statusTitle = "✅ Attendance Recorded";
            _statusSubtitle = "Status: Provisional (Awaiting verification)";
            _statusIcon = Icons.check_circle;
            _statusColor = Colors.green;
            _isScanning = false;
          });
        },
        onCheckInError: (error) {
          // Show a short user-friendly message, not the raw exception
          String cleanError = error;
          if (error.contains('PlatformException') || error.contains('SecurityException')) {
            cleanError = "Bluetooth permission denied. Please grant Bluetooth & Location permissions in Settings.";
          } else if (error.length > 120) {
            cleanError = error.substring(0, 120);
          }
          setState(() {
            _statusTitle = "❌ Check-in Failed";
            _statusSubtitle = cleanError;
            _statusIcon = Icons.error;
            _statusColor = Colors.red;
            _isScanning = false;
          });
        },
        onNoSession: () {
          if (_scanRetryCount < _maxScanRetries && mounted) {
            _scanRetryCount++;
            setState(() {
              _statusTitle = "No beacon found — retrying ($_scanRetryCount/$_maxScanRetries)";
              _statusSubtitle = "Scanning again in 10 seconds...";
              _statusIcon = Icons.refresh;
              _statusColor = Colors.orange;
              _isScanning = false;
            });
            _retryTimer?.cancel();
            _retryTimer = Timer(const Duration(seconds: 10), () {
              if (mounted && !_isScanning) {
                _startScanning();
              }
            });
          } else {
            setState(() {
              _statusTitle = "No active class session";
              _statusSubtitle = "Tap the refresh button to scan again.";
              _statusIcon = Icons.event_busy;
              _statusColor = Colors.grey;
              _isScanning = false;
            });
          }
        },
      );
    } catch (e) {
      setState(() {
        _statusTitle = "⚠️ Bluetooth Error";
        _statusSubtitle = "Please enable Bluetooth and try again.";
        _statusIcon = Icons.bluetooth_disabled;
        _statusColor = Colors.red;
        _isScanning = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Welcome, ${_studentName.isNotEmpty ? _studentName : 'Student'}",
          style: TextStyle(
            color: Colors.blue[900],
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _isScanning ? Icons.stop : Icons.refresh,
              color: Colors.blue[900],
            ),
            onPressed: _isScanning ? null : () {
              _scanRetryCount = 0; // Reset retry counter on manual refresh
              _retryTimer?.cancel();
              _loadStudentData();
              _startScanning();
            },
          ),
        ],
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Main Status Card
            StatusCard(
              icon: _statusIcon,
              title: _statusTitle,
              subtitle: _statusSubtitle,
              color: _statusColor,
              isLoading: _isScanning,
            ),
            
            const SizedBox(height: 24),

            // Weekly Progress Section
            Text(
              "Weekly Progress",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue[900],
              ),
            ),
            const SizedBox(height: 12),
            _buildProgressCard(),

            const SizedBox(height: 24),

            // Today's Classes Section
            Text(
              "Today's Classes",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue[900],
              ),
            ),
            const SizedBox(height: 12),
            if (_todayClasses.isEmpty)
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    'No classes scheduled for today',
                    style: TextStyle(color: Colors.grey[600], fontSize: 15),
                  ),
                ),
              )
            else
              ..._todayClasses.map((cls) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _buildClassCard(
                  cls['name'] as String,
                  cls['time'] as String,
                  cls['room'] as String,
                  cls['attended'] as bool,
                ),
              )),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    double progress = _totalClasses > 0 ? _attendedClasses / _totalClasses : 0;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "$_attendedClasses / $_totalClasses classes",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                "${(progress * 100).toInt()}%",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.blue[900],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 10,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.blue[700]!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClassCard(String name, String time, String room, bool attended) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: attended ? Colors.green[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: attended ? Border.all(color: Colors.green[300]!) : null,
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: attended ? Colors.green[100] : Colors.grey[300],
            child: Icon(
              attended ? Icons.check : Icons.schedule,
              color: attended ? Colors.green[700] : Colors.grey[600],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "$time • $room",
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          if (attended)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "Present",
                style: TextStyle(
                  color: Colors.green[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
