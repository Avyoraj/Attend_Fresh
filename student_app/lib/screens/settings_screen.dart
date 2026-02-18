import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ⚙️ Settings Screen
/// App settings with the "New Pipeline" toggle for beta features
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _newPipelineEnabled = false;
  bool _notificationsEnabled = true;
  bool _autoCheckIn = true;
  bool _darkMode = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _newPipelineEnabled = prefs.getBool('new_pipeline_enabled') ?? false;
      _notificationsEnabled = prefs.getBool('notifications_enabled') ?? true;
      _autoCheckIn = prefs.getBool('auto_check_in') ?? true;
      _darkMode = prefs.getBool('dark_mode') ?? false;
      _isLoading = false;
    });
  }

  Future<void> _saveSetting(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          "Settings",
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Beta Features Section
            _buildSectionHeader("🧪 Beta Features"),
            _buildSettingTile(
              icon: Icons.science,
              title: "New Attendance Pipeline",
              subtitle: "Enable the new Provisional → Confirm flow with RSSI streaming",
              value: _newPipelineEnabled,
              onChanged: (value) {
                setState(() => _newPipelineEnabled = value);
                _saveSetting('new_pipeline_enabled', value);
                _showPipelineInfo(value);
              },
              isBeta: true,
            ),

            const SizedBox(height: 16),

            // Attendance Section
            _buildSectionHeader("📡 Attendance"),
            _buildSettingTile(
              icon: Icons.bluetooth_searching,
              title: "Auto Check-In",
              subtitle: "Automatically check in when beacon is detected",
              value: _autoCheckIn,
              onChanged: (value) {
                setState(() => _autoCheckIn = value);
                _saveSetting('auto_check_in', value);
              },
            ),

            const SizedBox(height: 16),

            // Notifications Section
            _buildSectionHeader("🔔 Notifications"),
            _buildSettingTile(
              icon: Icons.notifications,
              title: "Push Notifications",
              subtitle: "Get notified about attendance status",
              value: _notificationsEnabled,
              onChanged: (value) {
                setState(() => _notificationsEnabled = value);
                _saveSetting('notifications_enabled', value);
              },
            ),

            const SizedBox(height: 16),

            // Appearance Section
            _buildSectionHeader("🎨 Appearance"),
            _buildSettingTile(
              icon: Icons.dark_mode,
              title: "Dark Mode",
              subtitle: "Use dark theme",
              value: _darkMode,
              onChanged: (value) {
                setState(() => _darkMode = value);
                _saveSetting('dark_mode', value);
              },
            ),

            const SizedBox(height: 16),

            // About Section
            _buildSectionHeader("ℹ️ About"),
            _buildInfoTile(
              icon: Icons.info_outline,
              title: "App Version",
              subtitle: "1.0.0 (Build 1)",
            ),
            _buildInfoTile(
              icon: Icons.code,
              title: "Backend URL",
              subtitle: "http://localhost:5000/api",
            ),
            _buildInfoTile(
              icon: Icons.bluetooth,
              title: "Beacon UUID",
              subtitle: "1a7f44b2-e25c-44a8...",
            ),

            const SizedBox(height: 24),

            // Debug Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: _showDebugInfo,
                icon: const Icon(Icons.bug_report),
                label: const Text("Show Debug Info"),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    bool isBeta = false,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isBeta ? Colors.purple[50] : Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: isBeta ? Border.all(color: Colors.purple[200]!) : null,
      ),
      child: SwitchListTile(
        secondary: CircleAvatar(
          backgroundColor: isBeta ? Colors.purple[100] : Colors.blue[100],
          child: Icon(
            icon,
            color: isBeta ? Colors.purple[700] : Colors.blue[700],
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isBeta) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.purple[200],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text(
                  "BETA",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 13,
          ),
        ),
        value: value,
        onChanged: onChanged,
        activeColor: isBeta ? Colors.purple : Colors.blue[700],
      ),
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.grey[300],
          child: Icon(icon, color: Colors.grey[700], size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 14,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  void _showPipelineInfo(bool enabled) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          enabled
              ? "🧪 New Pipeline ENABLED: Check-ins are now Provisional → Confirmed with RSSI streaming"
              : "New Pipeline disabled: Using standard check-in flow",
        ),
        backgroundColor: enabled ? Colors.purple : Colors.grey[700],
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showDebugInfo() {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Debug Info",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.blue[900],
              ),
            ),
            const SizedBox(height: 16),
            _debugRow("New Pipeline", _newPipelineEnabled ? "ON" : "OFF"),
            _debugRow("Auto Check-In", _autoCheckIn ? "ON" : "OFF"),
            _debugRow("Beacon UUID", "1a7f44b2-e25c-44a8-a634-3d0b98065d21"),
            _debugRow("RSSI Streaming", _newPipelineEnabled ? "45-min loop" : "Disabled"),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("Close"),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}
