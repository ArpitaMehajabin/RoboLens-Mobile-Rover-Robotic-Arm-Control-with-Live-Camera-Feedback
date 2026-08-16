import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_mjpeg/flutter_mjpeg.dart';
import 'settings_screen.dart';
import 'package:flutter/services.dart';
import 'main.dart';

class ControlScreen extends StatefulWidget {
  final WebSocketChannel channel;
  final Stream broadcastStream;
  final String piIp;
  final int wsPort;
  final int cameraPort;

  const ControlScreen({
    super.key,
    required this.channel,
    required this.broadcastStream,
    required this.piIp,
    required this.wsPort,
    required this.cameraPort,
  });

  @override
  State<ControlScreen> createState() => _ControlScreenState();
}

class _ControlScreenState extends State<ControlScreen> {
  // ---------------- Arm joint state ----------------
  final Map<String, double> _jointAngles = {
    "S1": 90, // Gripper
    "S2": 90, // Wrist Roll
    "S3": 90, // Wrist Pitch
    "S4": 90, // Elbow
    "S5": 90, // Shoulder
    "S6": 90, // Base
  };

  final Map<String, String> _jointLabels = {
    "S1": "Gripper",
    "S2": "W.Roll",
    "S3": "W.Pitch",
    "S4": "Elbow",
    "S5": "Shoulder",
    "S6": "Base",
  };

  // Per-joint angle limits — must match the Arduino firmware's servoMaxAngle[].
  final Map<String, double> _jointMax = {
    "S1": 120,
    "S2": 240,
    "S3": 240,
    "S4": 180,
    "S5": 180,
    "S6": 240,
  };

  final Map<String, Timer?> _debounceTimers = {};
  String? _activeDirection;

  // D-pad "heartbeat" — resends the active direction periodically so the
  // Arduino watchdog (2s timeout) never sees a gap while a button is held.
  Timer? _heartbeatTimer;
  static const _heartbeatInterval = Duration(milliseconds: 600);

  StreamSubscription? _wsSubscription;
  int? _distFront;

  // In-app alert badge (replaces the old SnackBar so it never covers controls)
  String? _alertText;
  Timer? _alertTimer;

  @override
  void initState() {
    super.initState();
    _wsSubscription = widget.broadcastStream.listen(_handleIncomingMessage);
  }

  void _handleIncomingMessage(dynamic raw) {
    try {
      final data = jsonDecode(raw as String) as Map<String, dynamic>;
      final type = data['type'];

      if (type == 'sensor') {
        setState(() => _distFront = data['front'] as int?);
      } else if (type == 'alert') {
        final msg = data['message'] as String? ?? '';
        _showAlertBadge(_friendlyAlert(msg));
      }
    } catch (_) {}
  }

  String _friendlyAlert(String raw) {
    if (raw == "OBSTACLE FRONT") return "Obstacle detected — stopped";
    if (raw == "WATCHDOG STOP") return "Connection lost — auto-stopped";
    if (raw == "EMERGENCY STOPPED") return "Emergency stop activated";
    return raw;
  }

  void _showAlertBadge(String message) {
    if (!mounted) return;
    _alertTimer?.cancel();
    setState(() => _alertText = message);
    _alertTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _alertText = null);
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

  void _onSliderChanged(String joint, double value) {
    setState(() => _jointAngles[joint] = value);
    _debounceTimers[joint]?.cancel();
    _debounceTimers[joint] = Timer(const Duration(milliseconds: 120), () {
      _sendCommand('{"type":"arm","joint":"$joint","angle":${value.round()}}');
    });
  }

  void _onSliderChangeEnd(String joint, double value) {
    _debounceTimers[joint]?.cancel();
    _sendCommand('{"type":"arm","joint":"$joint","angle":${value.round()}}');
  }

  void _startMove(String direction) {
    if (_activeDirection == direction) return;
    setState(() => _activeDirection = direction);
    _sendCommand('{"type":"move","direction":"$direction"}');

    // Keep re-sending the same direction while the button stays pressed.
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(_heartbeatInterval, (_) {
      if (_activeDirection == direction) {
        _sendCommand('{"type":"move","direction":"$direction"}');
      }
    });
  }

  void _stopMove() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    if (_activeDirection == null) return;
    setState(() => _activeDirection = null);
    _sendCommand('{"type":"move","direction":"stop"}');
  }

  void _emergencyStop() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
    setState(() => _activeDirection = null);
    _sendCommand('{"type":"emergency_stop"}');
  }

  @override
  void dispose() {
    for (final t in _debounceTimers.values) {
      t?.cancel();
    }
    _heartbeatTimer?.cancel();
    _alertTimer?.cancel();
    _wsSubscription?.cancel();
    widget.channel.sink.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cameraUrl = "http://${widget.piIp}:8080/?action=stream";
    final screenHeight = MediaQuery.of(context).size.height;
    final cameraHeight = (screenHeight * 0.26).clamp(150.0, 220.0);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        _goBackToConnectScreen();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1622),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTopBar(context),
                const SizedBox(height: 8),
                SizedBox(
                  height: cameraHeight,
                  child: Stack(
                    children: [_buildCameraFeed(cameraUrl), _buildAlertBadge()],
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildSectionTitle("ARM JOINT"),
                        const SizedBox(height: 6),
                        _buildArmSliders(),
                        const SizedBox(height: 16),
                        _buildSectionTitle("CHASSIS MOVEMENT"),
                        const SizedBox(height: 6),
                        _buildChassisControls(),
                        const SizedBox(height: 4),
                        _buildHintText(),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: _goBackToConnectScreen,
        ),
        const Spacer(),
        IconButton(
          icon: const Icon(Icons.settings, color: Colors.white),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  channel: widget.channel,
                  broadcastStream: widget.broadcastStream,
                  piIp: widget.piIp,
                  wsPort: widget.wsPort,
                  cameraPort: widget.cameraPort,
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildAlertBadge() {
    return Positioned(
      top: 8,
      left: 0,
      right: 0,
      child: Center(
        child: AnimatedOpacity(
          opacity: _alertText != null ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: IgnorePointer(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.85),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.redAccent.withOpacity(0.7)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.redAccent,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _alertText ?? "",
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _goBackToConnectScreen() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const ConnectScreen()));
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

  Widget _buildHintText() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF11202C),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.15)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: Colors.cyanAccent.withOpacity(0.8),
            size: 14,
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              "Press & hold directional buttons to move. Release to stop.",
              style: TextStyle(color: Colors.white54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraFeed(String cameraUrl) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: double.infinity,
            height: double.infinity,
            child: Mjpeg(
              stream: cameraUrl,
              isLive: true,
              error: (context, error, stack) {
                return Container(
                  color: const Color(0xFF16222E),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.videocam_outlined,
                        color: Colors.white24,
                        size: 40,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        "Camera Stream",
                        style: TextStyle(color: Colors.white38, fontSize: 13),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black45,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.greenAccent.withOpacity(0.8)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                SizedBox(width: 4),
                Text(
                  "LIVE",
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_distFront != null)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _distFront! < 30 ? Colors.redAccent : Colors.black54,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                "Front: ${_distFront}cm",
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildArmSliders() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _jointAngles.keys.map((joint) {
          final maxAngle = _jointMax[joint]!;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "${joint[1]}  ${_jointLabels[joint]}",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      "0 ~ ${maxAngle.round()}°",
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16,
                    ),
                    // Shows a floating "NN°" bubble above the thumb while dragging.
                    showValueIndicator: ShowValueIndicator.always,
                    valueIndicatorColor: Colors.cyanAccent,
                    valueIndicatorTextStyle: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  child: Slider(
                    value: _jointAngles[joint]!.clamp(0, maxAngle),
                    min: 0,
                    max: maxAngle,
                    label: "${_jointAngles[joint]!.round()}°",
                    activeColor: Colors.cyanAccent,
                    inactiveColor: Colors.white24,
                    onChanged: (value) => _onSliderChanged(joint, value),
                    onChangeEnd: (value) => _onSliderChangeEnd(joint, value),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildChassisControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _directionButton(Icons.keyboard_arrow_up, "F"),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _directionButton(Icons.keyboard_arrow_left, "L"),
                  const SizedBox(width: 42, height: 42),
                  _directionButton(Icons.keyboard_arrow_right, "R"),
                ],
              ),
              _directionButton(Icons.keyboard_arrow_down, "B"),
            ],
          ),
        ),
        GestureDetector(
          onTap: _emergencyStop,
          child: Container(
            width: 72,
            height: 72,
            decoration: const BoxDecoration(
              color: Colors.redAccent,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Text(
              "STOP",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _directionButton(IconData icon, String direction) {
    final bool isActive = _activeDirection == direction;
    return GestureDetector(
      onTapDown: (_) => _startMove(direction),
      onTapUp: (_) => _stopMove(),
      onTapCancel: () => _stopMove(),
      child: Container(
        width: 42,
        height: 42,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isActive ? Colors.cyanAccent : const Color(0xFF16222E),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.cyanAccent),
        ),
        child: Icon(icon, color: isActive ? Colors.black : Colors.cyanAccent),
      ),
    );
  }
}
