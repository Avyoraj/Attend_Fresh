import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/teacher_service.dart';
import '../services/teacher_auth_service.dart';
import 'live_dashboard.dart';
import 'teacher_auth_screen.dart';

/// 🏠 Teacher Home Screen
/// Start sessions, view classes, manage attendance
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TeacherService _teacherService = TeacherService();
  final TeacherAuthService _authService = TeacherAuthService();
  final SupabaseClient _supabase = Supabase.instance.client;
  
  bool _isStarting = false;
  String? _activeSessionId;

  // Teacher profile
  String _teacherName = '';
  String? _teacherId;  // UUID from teachers table

  // Real classes from Supabase
  List<Map<String, String>> _todayClasses = [];

  @override
  void initState() {
    super.initState();
    _loadTeacherData();
  }

  Future<void> _loadTeacherData() async {
    try {
      final profile = await _authService.getTeacherProfile();
      if (profile != null) {
        _teacherName = profile['name'] ?? '';
        _teacherId = profile['id'];

        // Fetch classes taught by this teacher
        final classes = await _supabase
            .from('classes')
            .select('class_id, name, room_id')
            .eq('teacher_id', _teacherId!)
            .eq('is_active', true);

        _todayClasses = (classes as List).map<Map<String, String>>((c) {
          return {
            'id': c['class_id'] as String? ?? '',
            'name': c['name'] as String? ?? '',
            'room': c['room_id'] as String? ?? '',
            'time': '',
          };
        }).toList();

        // If no classes assigned, show a default list for demo
        if (_todayClasses.isEmpty) {
          _todayClasses = [
            {'id': 'CS101', 'name': 'Data Structures', 'time': '9:00 AM', 'room': 'ROOM_01'},
            {'id': 'CS201', 'name': 'Algorithms', 'time': '11:00 AM', 'room': 'ROOM_01'},
            {'id': 'CS301', 'name': 'Database Systems', 'time': '2:00 PM', 'room': 'ROOM_01'},
          ];
        }
      } else {
        final user = _supabase.auth.currentUser;
        _teacherName = user?.email?.split('@').first ?? 'Teacher';
      }

      // Check for any active session
      final activeSessions = await _supabase
          .from('sessions')
          .select('id')
          .eq('status', 'active')
          .limit(1);
      
      if ((activeSessions as List).isNotEmpty) {
        _activeSessionId = activeSessions[0]['id'];
      }

      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Error loading teacher data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Teacher Dashboard",
          style: TextStyle(
            color: Colors.indigo[900],
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.indigo[900]),
            onPressed: _loadTeacherData,
          ),
          IconButton(
            icon: Icon(Icons.logout, color: Colors.indigo[900]),
            onPressed: () async {
              await _authService.signOut();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const TeacherAuthScreen()),
                  (route) => false,
                );
              }
            },
          ),
        ],
      ),
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome Header
            _buildWelcomeCard(),
            
            const SizedBox(height: 24),

            // Quick Actions
            Text(
              "Quick Actions",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo[900],
              ),
            ),
            const SizedBox(height: 12),
            _buildQuickActions(),

            const SizedBox(height: 24),

            // Today's Classes
            Text(
              "Today's Classes",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.indigo[900],
              ),
            ),
            const SizedBox(height: 12),
            ..._todayClasses.map((c) => _buildClassCard(c)),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.indigo[700]!, Colors.indigo[900]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 30,
            backgroundColor: Colors.white,
            child: Icon(Icons.person, size: 35, color: Colors.indigo),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  "Welcome back,",
                  style: TextStyle(color: Colors.white70, fontSize: 14),
                ),
                Text(
                  _teacherName.isNotEmpty ? _teacherName : "Teacher",
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _activeSessionId != null 
                      ? "🟢 Session Active" 
                      : "No active session",
                  style: TextStyle(
                    color: _activeSessionId != null 
                        ? Colors.greenAccent 
                        : Colors.white60,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Row(
      children: [
        Expanded(
          child: _buildActionCard(
            icon: Icons.play_circle_filled,
            label: "Start Session",
            color: Colors.green,
            onTap: () => _showStartSessionDialog(),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            icon: Icons.dashboard,
            label: "Live Dashboard",
            color: Colors.blue,
            onTap: _activeSessionId != null 
                ? () => _openLiveDashboard() 
                : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildActionCard(
            icon: Icons.history,
            label: "History",
            color: Colors.orange,
            onTap: () {},
          ),
        ),
      ],
    );
  }

  Widget _buildActionCard({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
  }) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20),
        decoration: BoxDecoration(
          color: isEnabled ? color.withOpacity(0.1) : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isEnabled ? color.withOpacity(0.3) : Colors.grey[300]!,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: isEnabled ? color : Colors.grey, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: TextStyle(
                color: isEnabled ? color : Colors.grey,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClassCard(Map<String, String> classInfo) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
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
          Container(
            width: 4,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.indigo,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  classInfo['name']!,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${classInfo['id']} • ${classInfo['time']}",
                  style: TextStyle(color: Colors.grey[600], fontSize: 13),
                ),
                Text(
                  classInfo['room']!,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                ),
              ],
            ),
          ),
          ElevatedButton(
            onPressed: _isStarting ? null : () => _startSessionForClass(classInfo),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: _isStarting
                ? const SizedBox(
                    height: 18, width: 18,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text("Start"),
          ),
        ],
      ),
    );
  }

  void _showStartSessionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Start New Session"),
        content: const Text("Select a class from Today's Classes to start a session."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK"),
          ),
        ],
      ),
    );
  }

  Future<void> _startSessionForClass(Map<String, String> classInfo) async {
    if (_teacherId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("❌ Teacher profile not loaded"), backgroundColor: Colors.red),
      );
      return;
    }

    // Prevent starting a new session if one is already active
    if (_activeSessionId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("⚠️ A session is already active. End it before starting a new one."),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isStarting = true);

    final session = await _teacherService.startSession(
      classId: classInfo['id']!,
      className: classInfo['name']!,
      roomId: classInfo['room'] ?? 'ROOM_01',
      teacherId: _teacherId!,
      teacherName: _teacherName,
    );

    setState(() => _isStarting = false);

    if (session != null) {
      setState(() => _activeSessionId = session['id']);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🚀 Session started for ${classInfo['name']}"),
            backgroundColor: Colors.green,
          ),
        );

        // Navigate to live dashboard and handle result when it pops
        final sessionEnded = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => LiveDashboard(
              sessionId: session['id'],
              className: classInfo['name']!,
            ),
          ),
        );

        // If session was ended from the dashboard, clear local state
        if (sessionEnded == true && mounted) {
          setState(() => _activeSessionId = null);
          _loadTeacherData(); // Refresh class list
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("❌ Failed to start session. Room may already have active session."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _openLiveDashboard() async {
    if (_activeSessionId != null) {
      final sessionEnded = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (context) => LiveDashboard(
            sessionId: _activeSessionId!,
            className: "Active Session",
          ),
        ),
      );

      if (sessionEnded == true && mounted) {
        setState(() => _activeSessionId = null);
        _loadTeacherData();
      }
    }
  }
}
