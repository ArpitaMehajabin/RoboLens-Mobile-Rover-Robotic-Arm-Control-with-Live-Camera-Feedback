import 'dart:async';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'main.dart' show kAlertsTopic, kAlertsPrefKey;

class SettingsScreen extends StatefulWidget {
  final WebSocketChannel channel;
  final Stream broadcastStream;
  final String piIp;
  final int wsPort;
  final int cameraPort;

  const SettingsScreen({
    super.key,
    required this.channel,
    required this.broadcastStream,
    required this.piIp,
    required this.wsPort,
    required this.cameraPort,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _chassisSpeed = "medium";
  String _armSpeed = "medium";
  bool _alertsEnabled = true;
  bool _isConnected = true;

  StreamSubscription? _wsSub;

  static const _chassisSpeedKey = "chassis_speed";
  static const _armSpeedKey = "arm_speed";

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    // broadcastStream is shared with ControlScreen (it's a broadcast stream),
    // so listening here too is safe and doesn't interfere with it.
    _wsSub = widget.broadcastStream.listen(
      (_) {
        if (mounted && !_isConnected) setState(() => _isConnected = true);
      },
      onError: (_) {
        if (mounted) setState(() => _isConnected = false);
      },
      onDone: () {
        if (mounted) setState(() => _isConnected = false);
      },
    );
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _chassisSpeed = prefs.getString(_chassisSpeedKey) ?? "medium";
      _armSpeed = prefs.getString(_armSpeedKey) ?? "medium";
      _alertsEnabled = prefs.getBool(kAlertsPrefKey) ?? true;
    });
  }

  void _sendCommand(String jsonString) {
    try {
      widget.channel.sink.add(jsonString);
      debugPrint("Sent: $jsonString");
    } catch (e) {
      debugPrint("Send failed: $e");
    }
  }

  Future<void> _setChassisSpeed(String speed) async {
    setState(() => _chassisSpeed = speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_chassisSpeedKey, speed);
    _sendCommand('{"type":"settings","target":"speed","value":"$speed"}');
  }

  Future<void> _setArmSpeed(String speed) async {
    setState(() => _armSpeed = speed);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_armSpeedKey, speed);
    _sendCommand('{"type":"settings","target":"armSpeed","value":"$speed"}');
  }

  Future<void> _toggleAlerts(bool value) async {
    setState(() => _alertsEnabled = value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAlertsPrefKey, value);
    try {
      if (value) {
        await FirebaseMessaging.instance.subscribeToTopic(kAlertsTopic);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(kAlertsTopic);
      }
    } catch (e) {
      debugPrint("FCM topic toggle failed: $e");
    }
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B1622),
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildConnectionCard(),
                    const SizedBox(height: 24),
                    _buildSectionTitle("ARM SERVO SPEED"),
                    const SizedBox(height: 8),
                    _speedTile("Slow", "slow", _armSpeed, _setArmSpeed),
                    _speedTile("Medium", "medium", _armSpeed, _setArmSpeed),
                    _speedTile("Fast", "fast", _armSpeed, _setArmSpeed),
                    const SizedBox(height: 24),
                    _buildSectionTitle("CHASSIS SERVO SPEED"),
                    const SizedBox(height: 8),
                    _speedTile("Slow", "slow", _chassisSpeed, _setChassisSpeed),
                    _speedTile(
                      "Medium",
                      "medium",
                      _chassisSpeed,
                      _setChassisSpeed,
                    ),
                    _speedTile("Fast", "fast", _chassisSpeed, _setChassisSpeed),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
          const Expanded(
            child: Text(
              "Settings",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.cyanAccent,
        fontWeight: FontWeight.bold,
        fontSize: 12,
        letterSpacing: 1,
      ),
    );
  }

  Widget _buildConnectionCard() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "CONNECTION",
                  style: TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    letterSpacing: 1,
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _isConnected
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _isConnected ? "Connected" : "Disconnected",
                      style: TextStyle(
                        color: _isConnected
                            ? Colors.greenAccent
                            : Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _divider(),
          _infoRow(Icons.smart_toy_outlined, "Robot IP", widget.piIp),
          _divider(),
          _infoRow(Icons.wifi, "WebSocket Port", widget.wsPort.toString()),
          _divider(),
          _infoRow(
            Icons.camera_alt_outlined,
            "Camera Port",
            widget.cameraPort.toString(),
          ),
          _divider(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: const [
                    Icon(
                      Icons.notifications_outlined,
                      color: Colors.white70,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      "Alerts",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
                Switch(
                  value: _alertsEnabled,
                  activeColor: Colors.cyanAccent,
                  onChanged: _toggleAlerts,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white70, size: 18),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ],
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _divider() =>
      Divider(height: 1, color: Colors.cyanAccent.withOpacity(0.15));

  Widget _speedTile(
    String label,
    String value,
    String currentValue,
    Future<void> Function(String) onSelect,
  ) {
    final bool isSelected = currentValue == value;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: SwitchListTile(
        value: isSelected,
        activeColor: Colors.cyanAccent,
        title: Text(label, style: const TextStyle(color: Colors.white)),
        onChanged: (_) => onSelect(value),
      ),
    );
  }
}
