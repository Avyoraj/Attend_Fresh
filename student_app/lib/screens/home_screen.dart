import 'package:flutter/material.dart';
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
  
  // UI State
  bool _isScanning = false;
  String _statusTitle = "No Attendance Yet";
  String _statusSubtitle = "Move near a beacon to check in";
  IconData _statusIcon = Icons.access_time_filled;
  Color _statusColor = Colors.grey;

  // Weekly stats (mock data for now)
  final int _attendedClasses = 12;
  final int _totalClasses = 15;

  @override
  void initState() {
    super.initState();
    _startScanning();
  }

  Future<void> _startScanning() async {
    setState(() {
      _isScanning = true;
      _statusTitle = "🔍 Searching for classroom beacon...";
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
          setState(() {
            _statusTitle = "❌ Check-in Failed";
            _statusSubtitle = error;
            _statusIcon = Icons.error;
            _statusColor = Colors.red;
            _isScanning = false;
          });
        },
        onNoSession: () {
          setState(() {
            _statusTitle = "No active class session";
            _statusSubtitle = "Wait for your teacher to start the session.";
            _statusIcon = Icons.event_busy;
            _statusColor = Colors.grey;
            _isScanning = false;
          });
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
          "Welcome, 0080",
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
            onPressed: _isScanning ? null : _startScanning,
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
            _buildClassCard("CS101 - Data Structures", "9:00 AM", "Room 101", true),
            const SizedBox(height: 8),
            _buildClassCard("CS201 - Algorithms", "11:00 AM", "Room 203", false),
            const SizedBox(height: 8),
            _buildClassCard("CS301 - Database Systems", "2:00 PM", "Room 105", false),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard() {
    double progress = _attendedClasses / _totalClasses;
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
