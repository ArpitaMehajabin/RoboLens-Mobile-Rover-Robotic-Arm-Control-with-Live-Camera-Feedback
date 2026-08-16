import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'control_screen.dart';

// ============================================================
// FIREBASE — Topic used for push alerts (obstacle / watchdog / e-stop)
// ============================================================
const String kAlertsTopic = "robolens_alerts";
const String kAlertsPrefKey = "alerts_enabled";

Future<void> _initFirebaseMessaging() async {
  try {
    await Firebase.initializeApp();

    final messaging = FirebaseMessaging.instance;

    // Ask for notification permission (Android 13+ / iOS)
    await messaging.requestPermission(alert: true, badge: true, sound: true);

    // Show notification even when app is in foreground (iOS)
    await messaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    // Respect saved user preference (Settings screen toggle). Default: ON.
    final prefs = await SharedPreferences.getInstance();
    final alertsEnabled = prefs.getBool(kAlertsPrefKey) ?? true;

    if (alertsEnabled) {
      await messaging.subscribeToTopic(kAlertsTopic);
    } else {
      await messaging.unsubscribeFromTopic(kAlertsTopic);
    }
  } catch (e) {
    // Never block app startup because of Firebase — robot control must still work.
    debugPrint("Firebase init failed: $e");
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initFirebaseMessaging();
  runApp(const RoboLensApp());
}

class RoboLensApp extends StatelessWidget {
  const RoboLensApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboLens',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.cyan,
        scaffoldBackgroundColor: const Color(0xFF0B1622),
      ),
      home: const SplashScreen(),
    );
  }
}

// ============================================================
// SPLASH SCREEN — tap anywhere to continue
// ============================================================
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _glowController;
  late final Animation<double> _glowAnimation;

  late final AnimationController _tapController;
  late final Animation<double> _tapAnimation;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 18, end: 34).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );

    _tapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _tapAnimation = Tween<double>(
      begin: 0,
      end: 6,
    ).animate(CurvedAnimation(parent: _tapController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _glowController.dispose();
    _tapController.dispose();
    super.dispose();
  }

  void _continue() {
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => const ConnectScreen()));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _continue,
      behavior: HitTestBehavior.opaque,
      child: Scaffold(
        backgroundColor: const Color(0xFF0B1622),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedBuilder(
                animation: _glowAnimation,
                builder: (context, child) {
                  return Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF16222E),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.cyanAccent.withOpacity(0.5),
                          blurRadius: _glowAnimation.value,
                          spreadRadius: _glowAnimation.value / 4,
                        ),
                      ],
                      border: Border.all(color: Colors.cyanAccent, width: 2),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(28.0),
                      child: Image.asset(
                        'assets/icon/robolens_icon.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stack) {
                          // Fallback in case the asset isn't wired up yet.
                          return const Icon(
                            Icons.precision_manufacturing_outlined,
                            size: 72,
                            color: Colors.cyanAccent,
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 28),
              const Text(
                "RoboLens",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                "Remote Robotic Manipulation",
                style: TextStyle(
                  color: Colors.cyanAccent,
                  fontSize: 13,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 44),
              LinearProgressIndicator(
                value: null,
                minHeight: 3,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Colors.cyanAccent,
                ),
              ).let((w) => SizedBox(width: 140, child: w)),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    "Tap anywhere to continue",
                    style: TextStyle(color: Colors.white38, fontSize: 13),
                  ),
                  const SizedBox(width: 8),
                  AnimatedBuilder(
                    animation: _tapAnimation,
                    builder: (context, child) {
                      return Transform.translate(
                        offset: Offset(0, _tapAnimation.value * -0.3),
                        child: Opacity(
                          opacity: 0.5 + (_tapAnimation.value / 12),
                          child: child,
                        ),
                      );
                    },
                    child: const Icon(
                      Icons.touch_app_rounded,
                      color: Colors.cyanAccent,
                      size: 18,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Small helper so we can keep the progress bar width-constrained inline.
extension _Let<T> on T {
  R let<R>(R Function(T) block) => block(this);
}

// ============================================================
// CONNECT SCREEN
// ============================================================
class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

enum _ConnStatus { idle, connecting, connected, error }

class _ConnectScreenState extends State<ConnectScreen> {
  final TextEditingController _ipController = TextEditingController(
    text: "robolens.local",
  );
  final FocusNode _ipFocusNode = FocusNode();

  static const _wsPort = 8765;
  static const _cameraPort = 8080;

  String _statusMessage = "";
  bool _isConnecting = false;
  _ConnStatus _status = _ConnStatus.idle;
  String? _lastConnectedIp;

  WebSocketChannel? _channel;
  Stream? _broadcastStream;
  bool _hasNavigated = false;
  StreamSubscription? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _loadSavedIp();
  }

  Future<void> _loadSavedIp() async {
    final prefs = await SharedPreferences.getInstance();
    final savedIp = prefs.getString('robot_ip');
    if (savedIp != null && mounted) {
      setState(() {
        _ipController.text = savedIp;
        _lastConnectedIp = savedIp;
      });
    }
  }

  Future<void> _saveIp(String ip) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('robot_ip', ip);
  }

  void _connectToRobot() {
    setState(() {
      _isConnecting = true;
      _status = _ConnStatus.connecting;
      _statusMessage = "Connecting...";
      _hasNavigated = false;
    });

    final ip = _ipController.text.trim();
    final wsUrl = "ws://$ip:$_wsPort";

    try {
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _broadcastStream = _channel!.stream.asBroadcastStream();
      _channel!.sink.add('{"type":"test","message":"Hello from Flutter app"}');

      _wsSubscription = _broadcastStream!.listen(
        (message) {
          setState(() {
            _isConnecting = false;
            _status = _ConnStatus.connected;
            _statusMessage = "Connected! Pi replied: $message";
          });

          if (!_hasNavigated) {
            _hasNavigated = true;
            _saveIp(ip);
            _wsSubscription?.cancel();
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => ControlScreen(
                  channel: _channel!,
                  broadcastStream: _broadcastStream!,
                  piIp: ip,
                  wsPort: _wsPort,
                  cameraPort: _cameraPort,
                ),
              ),
            );
          }
        },
        onError: (error) {
          setState(() {
            _isConnecting = false;
            _status = _ConnStatus.error;
            _statusMessage = "Error: $error";
          });
        },
        onDone: () {
          setState(() {
            _status = _ConnStatus.error;
            _statusMessage = "Connection closed";
          });
        },
      );
    } catch (e) {
      setState(() {
        _isConnecting = false;
        _status = _ConnStatus.error;
        _statusMessage = "Failed to connect: $e";
      });
    }
  }

  // ---------------- Exit confirmation (Back button) ----------------

  Future<bool?> _showExitConfirmationDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF16222E),
        title: const Text(
          "Exit RoboLens?",
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          "You will be taken back to the start screen. Continue?",
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              "Cancel",
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              "Exit",
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleBackPressed(BuildContext context) async {
    final shouldExit = await _showExitConfirmationDialog(context);
    if (shouldExit == true && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SplashScreen()),
      );
    }
  }

  // ---------------- UI helpers ----------------

  String get _statusTitle {
    switch (_status) {
      case _ConnStatus.idle:
        return "ROBOT READY";
      case _ConnStatus.connecting:
        return "CONNECTING";
      case _ConnStatus.connected:
        return "CONNECTED";
      case _ConnStatus.error:
        return "CONNECTION FAILED";
    }
  }

  String get _statusSubtitle {
    switch (_status) {
      case _ConnStatus.idle:
        return "Waiting for connection...";
      case _ConnStatus.connecting:
        return "Reaching out to the robot...";
      case _ConnStatus.connected:
        return "System is online";
      case _ConnStatus.error:
        return _statusMessage.isEmpty
            ? "Could not reach robot"
            : _statusMessage;
    }
  }

  Color get _statusDotColor {
    switch (_status) {
      case _ConnStatus.idle:
        return Colors.cyanAccent;
      case _ConnStatus.connecting:
        return Colors.amberAccent;
      case _ConnStatus.connected:
        return Colors.greenAccent;
      case _ConnStatus.error:
        return Colors.redAccent;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackPressed(context);
      },
      child: Scaffold(
        body: SafeArea(
          child: Column(
            children: [
              _buildTopBar(context),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 12),
                      _buildStatusCard(),
                      const SizedBox(height: 28),
                      const Text(
                        "Robot IP Address",
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildIpField(),
                      const SizedBox(height: 24),
                      _buildConnectButton(),
                      if (_lastConnectedIp != null) ...[
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Colors.greenAccent,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              "Last connected: $_lastConnectedIp",
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
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
            onPressed: () => _handleBackPressed(context),
          ),
          const Expanded(
            child: Text(
              "Connect to Robot",
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 48), // balances the back button
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(14),
        color: const Color(0xFF11202C),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0B1622),
              border: Border.all(color: Colors.cyanAccent.withOpacity(0.6)),
              boxShadow: [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.25),
                  blurRadius: 14,
                  spreadRadius: 1,
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Image.asset(
              'assets/icon/robolens_icon.png',
              fit: BoxFit.contain,
              errorBuilder: (context, error, stack) {
                return const Icon(
                  Icons.precision_manufacturing_outlined,
                  color: Colors.cyanAccent,
                );
              },
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _statusTitle,
                  style: const TextStyle(
                    color: Colors.cyanAccent,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusSubtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: _statusDotColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _status == _ConnStatus.connected
                          ? "System is online"
                          : _status == _ConnStatus.error
                          ? "System offline"
                          : "System is online",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIpField() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.cyanAccent.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF16222E),
      ),
      child: TextField(
        controller: _ipController,
        focusNode: _ipFocusNode,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        decoration: InputDecoration(
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          suffixIcon: IconButton(
            icon: const Icon(Icons.edit, color: Colors.cyanAccent, size: 20),
            onPressed: () {
              _ipFocusNode.requestFocus();
              _ipController.selection = TextSelection(
                baseOffset: 0,
                extentOffset: _ipController.text.length,
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildConnectButton() {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: LinearGradient(
          colors: _isConnecting
              ? [Colors.grey.shade700, Colors.grey.shade800]
              : [Colors.cyanAccent, Colors.cyan.shade700],
        ),
        boxShadow: _isConnecting
            ? []
            : [
                BoxShadow(
                  color: Colors.cyanAccent.withOpacity(0.35),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(30),
          onTap: _isConnecting ? null : _connectToRobot,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isConnecting ? Icons.sync : Icons.podcasts,
                  color: const Color(0xFF0B1622),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  _isConnecting ? "CONNECTING..." : "CONNECT",
                  style: const TextStyle(
                    color: Color(0xFF0B1622),
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
