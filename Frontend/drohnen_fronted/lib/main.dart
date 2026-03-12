import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:provider/provider.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (_) => DroneState(),
      child: const RoboMasterApp(),
    ),
  );
}

class RoboMasterApp extends StatelessWidget {
  const RoboMasterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drohnen Steuerung',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        colorScheme: ColorScheme.dark(
          primary: Colors.blue,
          secondary: Colors.blueAccent,
          surface: const Color(0xFF1E1E1E),
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      home: const DroneControlScreen(),
    );
  }
}

// --- State Management ---

class DroneState extends ChangeNotifier {
  String _serverIp = '192.168.10.1';
  String _serverPort = '8000';
  bool _connected = false;
  bool _flying = false;
  String? _error;

  // Telemetry
  String _battery = '--';
  String _height = '--';
  String _temperature = '--';
  String _speed = '--';
  String _flightTime = '--';

  // Video
  Uint8List? _currentFrame;
  WebSocketChannel? _videoChannel;
  WebSocketChannel? _rcChannel;
  Timer? _telemetryTimer;

  String get serverIp => _serverIp;
  String get serverPort => _serverPort;
  bool get connected => _connected;
  bool get flying => _flying;
  String? get error => _error;
  String get battery => _battery;
  String get height => _height;
  String get temperature => _temperature;
  String get speed => _speed;
  String get flightTime => _flightTime;
  Uint8List? get currentFrame => _currentFrame;

  String get _baseUrl => 'http://$_serverIp:$_serverPort';
  String get _wsUrl => 'ws://$_serverIp:$_serverPort';

  void setServerIp(String ip) {
    _serverIp = ip;
    notifyListeners();
  }

  void setServerPort(String port) {
    _serverPort = port;
    notifyListeners();
  }

  Future<void> connect() async {
    try {
      _error = null;
      notifyListeners();

      final response = await http.post(
        Uri.parse('$_baseUrl/connect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'ip': _serverIp}),
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        _connected = true;
        _startVideoStream();
        _startTelemetryPolling();
        _connectRcChannel();
      } else {
        _error = 'Verbindung fehlgeschlagen';
      }
    } catch (e) {
      _error = 'Server nicht erreichbar: $e';
    }
    notifyListeners();
  }

  Future<void> disconnect() async {
    try {
      await http.post(
        Uri.parse('$_baseUrl/disconnect'),
        headers: {'Content-Type': 'application/json'},
      );
    } catch (_) {}
    _cleanup();
    _connected = false;
    _flying = false;
    notifyListeners();
  }

  void _cleanup() {
    _telemetryTimer?.cancel();
    _telemetryTimer = null;
    _videoChannel?.sink.close();
    _videoChannel = null;
    _rcChannel?.sink.close();
    _rcChannel = null;
    _currentFrame = null;
  }

  void _startVideoStream() {
    _videoChannel = WebSocketChannel.connect(Uri.parse('$_wsUrl/video'));
    _videoChannel!.stream.listen(
      (data) {
        if (data is String) {
          _currentFrame = base64Decode(data);
          notifyListeners();
        }
      },
      onError: (_) {},
      onDone: () {},
    );
  }

  void _connectRcChannel() {
    _rcChannel = WebSocketChannel.connect(Uri.parse('$_wsUrl/rc'));
  }

  void sendRc(int a, int b, int c, int d) {
    if (_rcChannel != null && _connected) {
      _rcChannel!.sink.add(jsonEncode({'a': a, 'b': b, 'c': c, 'd': d}));
    }
  }

  void _startTelemetryPolling() {
    _telemetryTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (!_connected) return;
      try {
        final response = await http.get(
          Uri.parse('$_baseUrl/telemetry'),
        ).timeout(const Duration(seconds: 5));
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final t = data['data'];
          _battery = '${t['battery']}';
          _height = '${t['height']}';
          _temperature = '${t['temp']}';
          _speed = '${t['speed']}';
          _flightTime = '${t['flight_time']}';
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  Future<void> sendCommand(String command, {Map<String, dynamic>? args}) async {
    if (!_connected) return;
    try {
      await http.post(
        Uri.parse('$_baseUrl/command'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'command': command, 'args': args ?? {}}),
      );
      if (command == 'takeoff') {
        _flying = true;
        notifyListeners();
      } else if (command == 'land' || command == 'emergency') {
        _flying = false;
        notifyListeners();
      }
    } catch (e) {
      _error = 'Befehl fehlgeschlagen: $e';
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _cleanup();
    super.dispose();
  }
}

// --- Main Screen ---

class DroneControlScreen extends StatefulWidget {
  const DroneControlScreen({super.key});

  @override
  State<DroneControlScreen> createState() => _DroneControlScreenState();
}

class _DroneControlScreenState extends State<DroneControlScreen> {
  final TextEditingController _ipController = TextEditingController(text: '192.168.10.1');
  final TextEditingController _portController = TextEditingController(text: '8000');

  @override
  Widget build(BuildContext context) {
    final drone = context.watch<DroneState>();
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      body: SafeArea(
        child: isLandscape ? _buildLandscapeLayout(drone) : _buildPortraitLayout(drone),
      ),
    );
  }

  Widget _buildPortraitLayout(DroneState drone) {
    return Column(
      children: [
        _buildConnectionBar(drone),
        if (drone.error != null) _buildErrorBanner(drone.error!),
        Expanded(child: _buildVideoFeed(drone)),
        _buildTelemetryBar(drone),
        _buildControlArea(drone),
      ],
    );
  }

  Widget _buildLandscapeLayout(DroneState drone) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              _buildConnectionBar(drone),
              if (drone.error != null) _buildErrorBanner(drone.error!),
              Expanded(child: _buildVideoFeed(drone)),
              _buildTelemetryBar(drone),
            ],
          ),
        ),
        SizedBox(
          width: 300,
          child: _buildControlArea(drone),
        ),
      ],
    );
  }

  Widget _buildConnectionBar(DroneState drone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: const Color(0xFF1E1E1E),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 12,
            color: drone.connected ? Colors.green : Colors.red,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _ipController,
                enabled: !drone.connected,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: 'Drohnen IP',
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onChanged: (v) => drone.setServerIp(v),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 70,
            height: 36,
            child: TextField(
              controller: _portController,
              enabled: !drone.connected,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                hintText: 'Port',
                contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => drone.setServerPort(v),
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: drone.connected ? drone.disconnect : drone.connect,
            style: ElevatedButton.styleFrom(
              backgroundColor: drone.connected ? Colors.red : Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Text(
              drone.connected ? 'Trennen' : 'Verbinden',
              style: const TextStyle(fontSize: 13, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: Colors.red.shade900,
      child: Text(message, style: const TextStyle(fontSize: 12, color: Colors.white)),
    );
  }

  Widget _buildVideoFeed(DroneState drone) {
    return Container(
      color: Colors.black,
      child: drone.currentFrame != null
          ? Image.memory(
              drone.currentFrame!,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              width: double.infinity,
              height: double.infinity,
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off, size: 64, color: Colors.grey.shade700),
                  const SizedBox(height: 8),
                  Text(
                    drone.connected ? 'Warte auf Video...' : 'Kein Videosignal',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildTelemetryBar(DroneState drone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: const Color(0xFF1E1E1E),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _telemetryItem(Icons.battery_full, '${drone.battery}%', 'Batterie'),
          _telemetryItem(Icons.height, '${drone.height} cm', 'Höhe'),
          _telemetryItem(Icons.thermostat, '${drone.temperature}°C', 'Temp'),
          _telemetryItem(Icons.speed, drone.speed, 'Speed'),
          _telemetryItem(Icons.timer, '${drone.flightTime}s', 'Flugzeit'),
        ],
      ),
    );
  }

  Widget _telemetryItem(IconData icon, String value, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.blueAccent),
        Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
      ],
    );
  }

  Widget _buildControlArea(DroneState drone) {
    return Container(
      padding: const EdgeInsets.all(8),
      color: const Color(0xFF1A1A1A),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Action buttons row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _actionButton(
                'Start',
                Icons.flight_takeoff,
                Colors.green,
                drone.connected && !drone.flying
                    ? () => drone.sendCommand('takeoff')
                    : null,
              ),
              _actionButton(
                'Landen',
                Icons.flight_land,
                Colors.orange,
                drone.connected && drone.flying
                    ? () => drone.sendCommand('land')
                    : null,
              ),
              _actionButton(
                'NOT STOPP',
                Icons.dangerous,
                Colors.red,
                drone.connected
                    ? () => drone.sendCommand('emergency')
                    : null,
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Joysticks
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Left joystick: up/down + yaw (rotate)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Höhe / Drehen', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 130,
                    height: 130,
                    child: Joystick(
                      mode: JoystickMode.all,
                      listener: (details) {
                        if (!drone.connected || !drone.flying) return;
                        int d = (details.x * 100).round(); // yaw
                        int c = (details.y * -100).round(); // up/down
                        drone.sendRc(0, 0, c, d);
                      },
                    ),
                  ),
                ],
              ),
              // Right joystick: forward/backward + left/right
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Bewegung', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 130,
                    height: 130,
                    child: Joystick(
                      mode: JoystickMode.all,
                      listener: (details) {
                        if (!drone.connected || !drone.flying) return;
                        int a = (details.x * 100).round(); // left/right
                        int b = (details.y * -100).round(); // forward/backward
                        drone.sendRc(a, b, 0, 0);
                      },
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

  Widget _actionButton(String label, IconData icon, Color color, VoidCallback? onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: onPressed != null ? color : Colors.grey.shade800,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }
}
