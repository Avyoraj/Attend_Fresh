import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// 📜 History Screen
/// Shows attendance history with filtering options
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Present', 'Absent', 'Provisional'];

  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;
  String _studentId = '';

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // Get student record to find student_id
      final profile = await _supabase
          .from('students')
          .select('student_id')
          .eq('email', user.email!)
          .maybeSingle();

      if (profile != null) {
        _studentId = profile['student_id'] as String;
      }

      if (_studentId.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // Fetch attendance records joined with session info
      final records = await _supabase
          .from('attendance')
          .select('id, status, check_in_time, session_date, class_id, session_id, sessions(class_name, room_id, actual_start)')
          .eq('student_id', _studentId)
          .order('session_date', ascending: false)
          .order('check_in_time', ascending: false)
          .limit(50);

      _history = (records as List).map((r) {
        final session = r['sessions'] as Map<String, dynamic>?;
        return {
          'class': session?['class_name'] ?? r['class_id'] ?? 'Unknown',
          'date': _formatDate(r['session_date']),
          'time': _formatTime(session?['actual_start'] ?? r['check_in_time']),
          'status': r['status'] ?? 'unknown',
          'room': session?['room_id'] ?? '',
        };
      }).toList();
    } catch (e) {
      debugPrint('Error loading history: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return dateStr;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Attendance History",
          style: TextStyle(
            color: Colors.blue[900],
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: Colors.blue[900]),
            onPressed: _loadHistory,
          ),
        ],
      ),
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Filter Chips
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final filter = _filters[index];
                final isSelected = _selectedFilter == filter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(filter),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() => _selectedFilter = filter);
                    },
                    selectedColor: Colors.blue[100],
                    checkmarkColor: Colors.blue[900],
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.blue[900] : Colors.grey[700],
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                );
              },
            ),
          ),

          // History List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredHistory.isEmpty
                    ? Center(
                        child: Text(
                          'No attendance records found',
                          style: TextStyle(color: Colors.grey[600], fontSize: 16),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filteredHistory.length,
                        itemBuilder: (context, index) {
                          final record = _filteredHistory[index];
                          return _buildHistoryCard(record);
                        },
                      ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredHistory {
    if (_selectedFilter == 'All') return _history;
    return _history.where((record) {
      switch (_selectedFilter) {
        case 'Present':
          return record['status'] == 'confirmed';
        case 'Absent':
          return record['status'] == 'absent';
        case 'Provisional':
          return record['status'] == 'provisional';
        default:
          return true;
      }
    }).toList();
  }

  Widget _buildHistoryCard(Map<String, dynamic> record) {
    final status = record['status'] as String;
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (status) {
      case 'confirmed':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Present';
        break;
      case 'provisional':
        statusColor = Colors.orange;
        statusIcon = Icons.pending;
        statusText = 'Provisional';
        break;
      case 'absent':
        statusColor = Colors.red;
        statusIcon = Icons.cancel;
        statusText = 'Absent';
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.help;
        statusText = 'Unknown';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
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
                  record['class'],
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "${record['date']} • ${record['time']}",
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 13,
                  ),
                ),
                Text(
                  record['room'],
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
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
