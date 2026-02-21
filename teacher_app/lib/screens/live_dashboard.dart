import 'dart:async';
import 'package:flutter/material.dart';
import '../services/teacher_service.dart';
import '../services/beacon_monitor.dart';
import 'verification_screen.dart';

/// 📊 Live Dashboard
/// Real-time attendance monitoring with Supabase Realtime
class LiveDashboard extends StatefulWidget {
  final String sessionId;
  final String className;

  const LiveDashboard({
    super.key,
    required this.sessionId,
    required this.className,
  });

  @override
  State<LiveDashboard> createState() => _LiveDashboardState();
}

class _LiveDashboardState extends State<LiveDashboard> {
  final TeacherService _teacherService = TeacherService();
  final BeaconMonitor _beaconMonitor = BeaconMonitor();

  List<Map<String, dynamic>> _liveAttendees = [];
  Map<String, int> _stats = {'total': 0, 'confirmed': 0, 'provisional': 0, 'step2_verified': 0, 'flagged': 0};
  int? _currentMinor;
  bool _isBeaconSyncing = false;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _startPolling();
    _startBeaconMonitoring();
    _loadStats();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _beaconMonitor.dispose();
    super.dispose();
  }

  /// Poll attendance every 5 seconds (replaces Realtime to avoid timeout)
  void _startPolling() {
    // Initial fetch
    _fetchAttendance();
    // Poll every 5 seconds
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _fetchAttendance();
    });
  }

  Future<void> _fetchAttendance() async {
    final data = await _teacherService.fetchAttendance(widget.sessionId);
    if (mounted) {
      setState(() => _liveAttendees = data);
      _loadStats();
    }
  }

  /// 🔄 Start Beacon Monitoring for Rotation Detection
  void _startBeaconMonitoring() {
    _beaconMonitor.startMonitoring(
      onRotation: (newMinor) async {
        setState(() {
          _currentMinor = newMinor;
          _isBeaconSyncing = true;
        });

        // Sync with backend
        await _teacherService.syncBeaconRotation(widget.sessionId, newMinor);

        setState(() => _isBeaconSyncing = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("🔄 Beacon rotated! New Minor: $newMinor"),
              backgroundColor: Colors.blue,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      },
    );
  }

  /// 📊 Load Session Statistics
  Future<void> _loadStats() async {
    final stats = await _teacherService.getSessionStats(widget.sessionId);
    setState(() => _stats = stats);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.className,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
            Text(
              "Session ID: ${widget.sessionId.substring(0, 8)}...",
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo[900],
        elevation: 0,
        actions: [
          // Beacon Status Indicator
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: Icon(
                _isBeaconSyncing ? Icons.sync : Icons.bluetooth_connected,
                size: 18,
                color: _currentMinor != null ? Colors.green : Colors.orange,
              ),
              label: Text(
                _currentMinor != null ? "Minor: $_currentMinor" : "Scanning...",
                style: const TextStyle(fontSize: 12),
              ),
              backgroundColor: _currentMinor != null 
                  ? Colors.green[50] 
                  : Colors.orange[50],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.stop_circle, color: Colors.red),
            onPressed: _showEndSessionDialog,
          ),
        ],
      ),
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          // Stats Bar
          _buildStatsBar(),

          // Live Attendees List
          Expanded(
            child: _liveAttendees.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _liveAttendees.length,
                    itemBuilder: (context, index) {
                      return _buildAttendeeCard(_liveAttendees[index]);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _openVerificationScreen,
        icon: const Icon(Icons.verified_user),
        label: Text("Verify (${_stats['flagged']})"),
        backgroundColor: _stats['flagged']! > 0 ? Colors.orange : Colors.grey,
      ),
    );
  }

  Widget _buildStatsBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.white,
      child: Row(
        children: [
          _buildStatItem("Total", _stats['total']!, Colors.blue),
          _buildStatItem("Confirmed", _stats['confirmed']!, Colors.green),
          _buildStatItem("Verifying", (_stats['provisional']! + _stats['step2_verified']!), Colors.teal),
          _buildStatItem("Flagged", _stats['flagged']!, Colors.red),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, int value, Color color) {
    return Expanded(
      child: Column(
        children: [
          Text(
            "$value",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.people_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "Waiting for students...",
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Students will appear here when they check in",
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAttendeeCard(Map<String, dynamic> student) {
    final status = student['status'] as String? ?? 'unknown';
    
    Color statusColor;
    IconData statusIcon;
    
    switch (status) {
      case 'confirmed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'step2_verified':
        statusColor = Colors.teal;
        statusIcon = Icons.hourglass_top;
        break;
      case 'provisional':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        break;
      case 'flagged':
        statusColor = Colors.red;
        statusIcon = Icons.warning;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
    }

    return GestureDetector(
      onLongPress: () => _showStudentActions(student),
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: status == 'flagged' 
            ? Border.all(color: Colors.red[300]!, width: 2)
            : null,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: statusColor.withOpacity(0.2),
            child: Icon(statusIcon, color: statusColor),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Student: ${student['student_id'] ?? 'Unknown'}",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildInfoChip(
                      Icons.signal_cellular_alt,
                      "RSSI: ${student['rssi'] ?? 'N/A'}",
                    ),
                    const SizedBox(width: 8),
                    _buildInfoChip(
                      Icons.access_time,
                      _formatTime(student['check_in_time']),
                    ),
                  ],
                ),
              ],
            ),
          ),
          
          // Status Badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              status.toUpperCase(),
              style: TextStyle(
                color: statusColor,
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),

          // Verify Button for Flagged
          if (status == 'flagged') ...[
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.verified_user, color: Colors.green),
              onPressed: () => _confirmStudent(student),
            ),
          ],
        ],
      ),
    ));
  }

  Widget _buildInfoChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null) return "N/A";
    try {
      final dt = DateTime.parse(isoTime);
      return "${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}";
    } catch (e) {
      return "N/A";
    }
  }

  Future<void> _confirmStudent(Map<String, dynamic> student) async {
    final success = await _teacherService.confirmAttendance(
      student['id'],
      'TEACHER_UUID_01',
    );

    if (mounted && success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ ${student['student_id']} confirmed"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showStudentActions(Map<String, dynamic> student) {
    final studentId = student['student_id'] as String? ?? 'Unknown';
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  "Student: $studentId",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.verified_user, color: Colors.green),
                title: const Text("Confirm Attendance"),
                onTap: () {
                  Navigator.pop(ctx);
                  _confirmStudent(student);
                },
              ),
              ListTile(
                leading: const Icon(Icons.phonelink_erase, color: Colors.orange),
                title: const Text("Reset Device Binding"),
                subtitle: const Text("Allow student to check in from a new phone"),
                onTap: () {
                  Navigator.pop(ctx);
                  _resetDevice(studentId);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cancel, color: Colors.red),
                title: const Text("Mark Absent"),
                onTap: () {
                  Navigator.pop(ctx);
                  _teacherService.markAsAbsent(
                    student['id'],
                    'Marked absent by teacher from live dashboard',
                  );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text("❌ $studentId marked absent"),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resetDevice(String studentId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Reset Device?"),
        content: Text(
          "This will unbind $studentId from their current phone. "
          "They will need to check in again to bind a new device.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text("Reset"),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final success = await _teacherService.resetStudentDevice(studentId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success
              ? "🔓 Device reset for $studentId"
              : "❌ Failed to reset device"),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  void _openVerificationScreen() {
    final flaggedStudents = _liveAttendees
        .where((s) => s['status'] == 'flagged')
        .toList();

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => VerificationScreen(
          sessionId: widget.sessionId,
          flaggedStudents: flaggedStudents,
        ),
      ),
    );
  }

  void _showEndSessionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("End Session?"),
        content: const Text(
          "This will close the attendance window. "
          "Students will no longer be able to check in."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _endSession();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("End Session"),
          ),
        ],
      ),
    );
  }

  Future<void> _endSession() async {
    // 1. Stop beacon monitor FIRST so it doesn't sync to an ended session
    _beaconMonitor.stopMonitoring();

    // 2. Stop polling
    _pollTimer?.cancel();
    _pollTimer = null;

    // 3. End session on backend
    final success = await _teacherService.endSession(widget.sessionId);
    
    if (mounted) {
      if (success) {
        // Pop with result=true so home_screen knows to clear _activeSessionId
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("✅ Session ended successfully"),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Restart monitoring if end failed
        _startBeaconMonitoring();
        _startPolling();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Failed to end session"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}
