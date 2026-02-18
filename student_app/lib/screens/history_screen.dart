import 'package:flutter/material.dart';

/// 📜 History Screen
/// Shows attendance history with filtering options
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Present', 'Absent', 'Provisional'];

  // Mock attendance history data
  final List<Map<String, dynamic>> _history = [
    {
      'class': 'CS101 - Data Structures',
      'date': 'Feb 2, 2026',
      'time': '9:00 AM',
      'status': 'confirmed',
      'room': 'Room 101',
    },
    {
      'class': 'CS201 - Algorithms',
      'date': 'Feb 1, 2026',
      'time': '11:00 AM',
      'status': 'confirmed',
      'room': 'Room 203',
    },
    {
      'class': 'CS301 - Database Systems',
      'date': 'Feb 1, 2026',
      'time': '2:00 PM',
      'status': 'provisional',
      'room': 'Room 105',
    },
    {
      'class': 'CS101 - Data Structures',
      'date': 'Jan 31, 2026',
      'time': '9:00 AM',
      'status': 'absent',
      'room': 'Room 101',
    },
    {
      'class': 'CS201 - Algorithms',
      'date': 'Jan 30, 2026',
      'time': '11:00 AM',
      'status': 'confirmed',
      'room': 'Room 203',
    },
  ];

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
            child: ListView.builder(
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
