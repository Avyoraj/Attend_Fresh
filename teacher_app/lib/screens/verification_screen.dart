import 'package:flutter/material.dart';
import '../services/teacher_service.dart';

/// ✅ Verification Screen
/// Physical verification for flagged students
class VerificationScreen extends StatefulWidget {
  final String sessionId;
  final List<Map<String, dynamic>> flaggedStudents;

  const VerificationScreen({
    super.key,
    required this.sessionId,
    required this.flaggedStudents,
  });

  @override
  State<VerificationScreen> createState() => _VerificationScreenState();
}

class _VerificationScreenState extends State<VerificationScreen> {
  final TeacherService _teacherService = TeacherService();
  late List<Map<String, dynamic>> _students;
  final Set<String> _verifiedIds = {};

  @override
  void initState() {
    super.initState();
    _students = List.from(widget.flaggedStudents);
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _students.length - _verifiedIds.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Physical Verification"),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // Header Info
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            color: Colors.orange[50],
            child: Column(
              children: [
                Icon(Icons.warning_amber, size: 48, color: Colors.orange[700]),
                const SizedBox(height: 12),
                Text(
                  "$pendingCount Students Require Verification",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange[900],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "These students have been flagged for suspicious RSSI patterns.\n"
                  "Please verify their physical presence.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orange[700]),
                ),
              ],
            ),
          ),

          // Student List
          Expanded(
            child: _students.isEmpty
                ? _buildNoFlaggedState()
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _students.length,
                    itemBuilder: (context, index) {
                      return _buildVerificationCard(_students[index]);
                    },
                  ),
          ),
        ],
      ),
      bottomNavigationBar: _students.isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _markAllAbsent,
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        label: const Text("Mark All Absent"),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.red,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _confirmAllVerified,
                        icon: const Icon(Icons.check_circle),
                        label: const Text("Confirm All"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildNoFlaggedState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 80, color: Colors.green[300]),
          const SizedBox(height: 16),
          Text(
            "All Clear!",
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.green[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "No students require physical verification",
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard(Map<String, dynamic> student) {
    final isVerified = _verifiedIds.contains(student['id']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isVerified ? Colors.green[50] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isVerified ? Colors.green[300]! : Colors.orange[300]!,
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: isVerified ? Colors.green[100] : Colors.orange[100],
                child: Icon(
                  isVerified ? Icons.check : Icons.person,
                  color: isVerified ? Colors.green : Colors.orange,
                ),
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
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Device: ${student['device_id']?.toString().substring(0, 8) ?? 'N/A'}...",
                      style: TextStyle(color: Colors.grey[600], fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (isVerified)
                const Chip(
                  label: Text("VERIFIED", style: TextStyle(fontSize: 10)),
                  backgroundColor: Colors.green,
                  labelStyle: TextStyle(color: Colors.white),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // Suspicious Pattern Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.analytics, color: Colors.red[700], size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Flagged: Similar RSSI pattern detected with another student",
                    style: TextStyle(color: Colors.red[700], fontSize: 13),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Action Buttons
          if (!isVerified)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _markAbsent(student),
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text("Absent"),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _confirmPresent(student),
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text("Present"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<void> _confirmPresent(Map<String, dynamic> student) async {
    final success = await _teacherService.confirmAttendance(
      student['id'],
      'TEACHER_UUID_01',
    );

    if (success) {
      setState(() {
        _verifiedIds.add(student['id']);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("✅ ${student['student_id']} marked present"),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _markAbsent(Map<String, dynamic> student) async {
    final success = await _teacherService.markAsAbsent(
      student['id'],
      'Physical verification failed - Student not present',
    );

    if (success) {
      setState(() {
        _students.remove(student);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("❌ ${student['student_id']} marked absent (Proxy detected)"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _confirmAllVerified() async {
    for (final student in _students) {
      if (!_verifiedIds.contains(student['id'])) {
        await _teacherService.confirmAttendance(student['id'], 'TEACHER_UUID_01');
      }
    }

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("✅ All flagged students confirmed"),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _markAllAbsent() async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Mark All Absent?"),
        content: const Text(
          "This will mark all flagged students as absent (proxy detected). "
          "This action cannot be undone."
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              for (final student in _students) {
                await _teacherService.markAsAbsent(
                  student['id'],
                  'Bulk marked absent - Physical verification not performed',
                );
              }

              if (mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("❌ All flagged students marked absent"),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Mark All Absent"),
          ),
        ],
      ),
    );
  }
}
