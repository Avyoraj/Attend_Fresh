import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'auth_screen.dart';

/// 👤 Profile Screen
/// Displays student info and attendance statistics
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final AuthService _authService = AuthService();

  String _name = '';
  String _studentId = '';
  String _email = '';
  int _year = 0;
  String _section = '';
  int _totalClasses = 0;
  int _attended = 0;
  int _missed = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;
      _email = user.email ?? '';

      final profile = await _supabase
          .from('students')
          .select()
          .eq('email', user.email!)
          .maybeSingle();

      if (profile != null) {
        _name = profile['name'] ?? '';
        _studentId = profile['student_id'] ?? '';
        _year = profile['year'] ?? 0;
        _section = profile['section'] ?? '';
      }

      // Fetch overall attendance stats
      if (_studentId.isNotEmpty) {
        // Count all sessions the student could have attended (ended sessions for their classes)
        // Simplified: count all ended sessions
        final allSessions = await _supabase
            .from('sessions')
            .select('id')
            .eq('status', 'ended');

        _totalClasses = (allSessions as List).length;

        // Count student's confirmed + provisional attendance
        final attendedRecords = await _supabase
            .from('attendance')
            .select('id')
            .eq('student_id', _studentId)
            .inFilter('status', ['confirmed', 'provisional']);

        _attended = (attendedRecords as List).length;
        _missed = _totalClasses - _attended;
        if (_missed < 0) _missed = 0;
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: Text("Profile",
              style: TextStyle(color: Colors.blue[900], fontWeight: FontWeight.bold)),
          backgroundColor: Colors.white,
          elevation: 0,
        ),
        backgroundColor: Colors.white,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Profile",
          style: TextStyle(
            color: Colors.blue[900],
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Profile Header
            _buildProfileHeader(),
            
            const SizedBox(height: 24),

            // Stats Cards
            Row(
              children: [
                Expanded(child: _buildStatCard("Total Classes", "$_totalClasses", Colors.blue)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard("Attended", "$_attended", Colors.green)),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard("Missed", "$_missed", Colors.red)),
              ],
            ),

            const SizedBox(height: 24),

            // Attendance Rate Card
            _buildAttendanceRateCard(),

            const SizedBox(height: 24),

            // Info Section
            _buildInfoSection(),

            const SizedBox(height: 24),

            // Logout Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: OutlinedButton.icon(
                onPressed: () async {
                  await _authService.signOut();
                  if (context.mounted) {
                    Navigator.of(context).pushAndRemoveUntil(
                      MaterialPageRoute(builder: (_) => const AuthScreen()),
                      (route) => false,
                    );
                  }
                },
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Logout', style: TextStyle(color: Colors.red, fontSize: 16)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    final deptText = _year > 0
        ? 'Year $_year${_section.isNotEmpty ? ' • Section $_section' : ''}'
        : '';
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue[700]!, Colors.blue[900]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white,
            child: Icon(Icons.person, size: 50, color: Colors.blue),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _name.isNotEmpty ? _name : 'Student',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _studentId.isNotEmpty ? 'ID: $_studentId' : '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 14,
                  ),
                ),
                if (deptText.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    deptText,
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[700],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceRateCard() {
    final double rate = _totalClasses > 0 ? (_attended / _totalClasses) * 100 : 0;
    String rateLabel;
    Color rateColor;
    if (rate >= 90) {
      rateLabel = 'Excellent';
      rateColor = Colors.green;
    } else if (rate >= 75) {
      rateLabel = 'Good';
      rateColor = Colors.blue;
    } else if (rate >= 60) {
      rateLabel = 'Average';
      rateColor = Colors.orange;
    } else {
      rateLabel = 'Low';
      rateColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Attendance Rate",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: rateColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  rateLabel,
                  style: TextStyle(
                    color: rateColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: 120,
                height: 120,
                child: CircularProgressIndicator(
                  value: rate / 100,
                  strokeWidth: 12,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(rateColor),
                ),
              ),
              Column(
                children: [
                  Text(
                    "${rate.toStringAsFixed(1)}%",
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    "$_attended/$_totalClasses",
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          _buildInfoTile(Icons.email, "Email", _email.isNotEmpty ? _email : 'N/A'),
          const Divider(height: 1),
          _buildInfoTile(Icons.badge, "Student ID", _studentId.isNotEmpty ? _studentId : 'N/A'),
          const Divider(height: 1),
          _buildInfoTile(Icons.school, "Year", _year > 0 ? 'Year $_year' : 'N/A'),
          const Divider(height: 1),
          _buildInfoTile(Icons.group, "Section", _section.isNotEmpty ? _section : 'N/A'),
        ],
      ),
    );
  }

  Widget _buildInfoTile(IconData icon, String label, String value) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue[100],
        child: Icon(icon, color: Colors.blue[700], size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          color: Colors.grey[600],
        ),
      ),
      subtitle: Text(
        value,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w500,
          color: Colors.black87,
        ),
      ),
    );
  }
}
