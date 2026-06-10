import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:drohnen_fronted/widgets/video_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../widgets/led_matrix_control.dart'; // Pfad ggf. anpassen

import '../video_stream_view.dart';
import '../models/flug_step.dart';
import '../widgets/glass_container.dart';
import '../widgets/flugkurse_dialog.dart';
import '../widgets/add_flugkurs_dialog.dart';

class DroneDashboard extends StatefulWidget {
  final String initialIp;

  const DroneDashboard({Key? key, required this.initialIp}) : super(key: key);

  @override
  State<DroneDashboard> createState() => _DroneDashboardState();
}

class _DroneDashboardState extends State<DroneDashboard> {
  bool isConnected = false;
  late String ipAddress;
  bool isRecording = false;
  bool aiVisionEnabled = false;
  bool ringModeEnabled = false;
  String _ringState = 'idle';

  // 2D Map State
  final List<Offset> _dronePath = [Offset.zero];
  double _currentDroneX = 0;
  double _currentDroneY = 0;
  double _droneYaw = 0;
  DateTime? _lastTelemetryTime;

  final String backendHost =
      '127.0.0.1:8000'; // Bei Android Emulator ggf. auf 10.0.2.2:8000 ändern
  WebSocketChannel? _rcChannel;
  Timer? _ringStatusTimer;
  String batteryLevel = '---';
  String droneHeight = '---';
  String droneSpeed = '---';
  String droneTime = '---';
  String droneTemp = '---';

  // RC Control State
  final FocusNode _focusNode = FocusNode();
  int _a = 0, _b = 0, _c = 0, _d = 0;

  // Recording State
  List<FlugStep> _recordedSteps = [];
  DateTime? _stepStartTime;
  String? _currentRecordingDirection;

  @override
  void initState() {
    super.initState();
    ipAddress = widget.initialIp;
  }

  Future<void> toggleConnection() async {
    if (isConnected) {
      // Trennen
      try {
        await http.post(Uri.parse('http://$backendHost/disconnect'));
      } catch (e) {
        debugPrint('Error disconnecting: $e');
      }
      _rcChannel?.sink.close();

      if (mounted) {
        _stopRingStatusPolling();
        setState(() {
          isConnected = false;
          ringModeEnabled = false;
          _ringState = 'idle';
          batteryLevel = '---';
          droneHeight = '---';
          droneSpeed = '---';
          droneTime = '---';
          droneTemp = '---';

          _dronePath.clear();
          _dronePath.add(Offset.zero);
          _currentDroneX = 0;
          _currentDroneY = 0;
          _droneYaw = 0;
          _lastTelemetryTime = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verbindung getrennt.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      // Verbinden
      try {
        final res = await http.post(
          Uri.parse('http://$backendHost/connect'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'ip': ipAddress}),
        );
        final data = jsonDecode(res.body);
        if (data['success'] == true) {
          _rcChannel = WebSocketChannel.connect(
            Uri.parse('ws://$backendHost/rc'),
          );
          _rcChannel!.stream.listen((message) {
            final msgData = jsonDecode(message);
            if (msgData['type'] == 'telemetry') {
              final tele = msgData['data'];
              if (mounted) {
                setState(() {
                  batteryLevel = (tele['battery']?.toString() ?? '---')
                      .replaceAll('%', '');
                  droneHeight = tele['height']?.toString() ?? '---';
                  droneSpeed = tele['speed']?.toString() ?? '---';
                  droneTime = tele['flight_time']?.toString() ?? '---';
                  droneTemp = tele['temp']?.toString() ?? '---';

                  if (tele['attitude'] != null) {
                    _droneYaw = (tele['attitude']['yaw'] ?? 0).toDouble();
                  }

                  if (tele['velocity'] != null) {
                    double vgx = -(tele['velocity']['vgx'] ?? 0).toDouble();
                    double vgy = -(tele['velocity']['vgy'] ?? 0).toDouble();

                    // Compute actual elapsed time for accurate dead-reckoning.
                    // Cap at 0.5s to avoid huge jumps after pauses.
                    final now = DateTime.now();
                    final dt = _lastTelemetryTime != null
                        ? (now.difference(_lastTelemetryTime!).inMilliseconds / 1000.0).clamp(0.0, 0.5)
                        : 0.1;
                    _lastTelemetryTime = now;

                    // Ignore tiny velocities (sensor noise when hovering).
                    const double deadzone = 4.0; // cm/s
                    if (vgx.abs() >= deadzone || vgy.abs() >= deadzone) {
                      // vgx = forward/backward (body frame), vgy = right/left (body frame).
                      // Rotate body-frame velocity into world frame using current yaw.
                      final double rad = _droneYaw * math.pi / 180.0;
                      final double dx = vgx * math.sin(rad) + vgy * math.cos(rad);
                      final double dy = vgx * math.cos(rad) - vgy * math.sin(rad);

                      _currentDroneX += dx * dt;
                      _currentDroneY -= dy * dt;
                      _dronePath.add(Offset(_currentDroneX, _currentDroneY));
                    }
                  }
                });
              }
            }
          });
          if (mounted) {
            setState(() {
              isConnected = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Verbunden!'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          throw Exception('${data['error']}');
        }
      } catch (e) {
        debugPrint('Fehler beim Verbinden: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fehler beim Verbinden: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  void _sendCommand(String command) {
    if (isConnected && _rcChannel != null) {
      if (isRecording) {
        if (command == 'takeoff' || command == 'land') {
          // Finish any ongoing RC direction recording
          if (_currentRecordingDirection != null && _stepStartTime != null) {
            final seconds =
                DateTime.now().difference(_stepStartTime!).inMilliseconds /
                1000.0;
            if (seconds >= 0.2) {
              final rounded = (seconds * 10).round() / 10.0;
              _recordedSteps.add(
                FlugStep(
                  direction: _currentRecordingDirection!,
                  seconds: rounded,
                ),
              );
            }
          }
          _currentRecordingDirection = null;
          _stepStartTime = null;

          _recordedSteps.add(
            FlugStep(direction: command, seconds: 5.0),
          ); // Fake duration
        }
      }
      _rcChannel!.sink.add(jsonEncode({"command": command}));
    }
  }

  @override
  void dispose() {
    _ringStatusTimer?.cancel();
    _focusNode.dispose();
    _rcChannel?.sink.close();
    super.dispose();
  }

  String? _getDirectionFromRC(int a, int b, int c, int d) {
    if (b > 0) return 'forward';
    if (b < 0) return 'backward';
    if (a < 0) return 'left';
    if (a > 0) return 'right';
    if (c > 0) return 'up';
    if (c < 0) return 'down';
    if (d < 0) return 'rotate_left';
    if (d > 0) return 'rotate_right';
    return null;
  }

  void _updateRC() {
    if (isConnected && _rcChannel != null) {
      _rcChannel!.sink.add(jsonEncode({"a": _a, "b": _b, "c": _c, "d": _d}));
    }
  }

  Future<void> _executeCourse(List<Map<String, dynamic>> commands) async {
    Navigator.of(context).pop(); // Dialog schließen

    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nicht verbunden!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Flugkurs gestartet...'),
        backgroundColor: Colors.blue,
      ),
    );

    for (var cmd in commands) {
      if (!isConnected) break; // Abbrechen, falls Verbindung getrennt wird

      try {
        await http.post(
          Uri.parse('http://$backendHost/command'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(cmd),
        );

        // Pausen einbauen, weil das Backend die Befehle asynchron sendet.
        // Die Drohne braucht Zeit für das Manöver.
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        debugPrint('Fehler bei Flugkurs-Befehl: $e');
      }
    }

    if (mounted && isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Flugkurs beendet!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _toggleRecording() {
    setState(() {
      isRecording = !isRecording;
    });

    if (isRecording) {
      _recordedSteps.clear();
      _currentRecordingDirection = _getDirectionFromRC(_a, _b, _c, _d);
      _stepStartTime = _currentRecordingDirection != null
          ? DateTime.now()
          : null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aufzeichnung gestartet!'),
          backgroundColor: Colors.blue,
        ),
      );
    } else {
      // Finish recording the last step if any
      if (_currentRecordingDirection != null && _stepStartTime != null) {
        final seconds =
            DateTime.now().difference(_stepStartTime!).inMilliseconds / 1000.0;
        if (seconds >= 0.2) {
          final rounded = (seconds * 10).round() / 10.0;
          _recordedSteps.add(
            FlugStep(direction: _currentRecordingDirection!, seconds: rounded),
          );
        }
      }
      _currentRecordingDirection = null;
      _stepStartTime = null;

      if (_recordedSteps.isNotEmpty) {
        _showSaveCourseDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Keine Schritte aufgezeichnet.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  void _showSaveCourseDialog() {
    final TextEditingController nameController = TextEditingController();
    bool saving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              title: const Text(
                'Flugkurs speichern',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${_recordedSteps.length} Schritte aufgezeichnet.',
                    style: const TextStyle(color: Colors.white54),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _recordedSteps.clear();
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'Verwerfen',
                    style: TextStyle(color: Colors.redAccent),
                  ),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          if (name.isEmpty) return;
                          setStateDialog(() => saving = true);
                          try {
                            final res = await http.post(
                              Uri.parse('http://$backendHost/flugkurs'),
                              headers: {'Content-Type': 'application/json'},
                              body: jsonEncode({
                                'name': name,
                                'commands': _recordedSteps
                                    .map((s) => s.toJson())
                                    .toList(),
                              }),
                            );
                            final data = jsonDecode(res.body);
                            if (data['success'] == true) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Kurs gespeichert!'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                              _recordedSteps.clear();
                            } else {
                              throw Exception(data['error']);
                            }
                          } catch (e) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Fehler: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                            setStateDialog(() => saving = false);
                          }
                        },
                  child: saving
                      ? const CircularProgressIndicator()
                      : const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showFlightCoursesDialog() {
    showDialog(
      context: context,
      builder: (context) => FlugkurseDialog( 
        backendHost: backendHost,
        isConnected: isConnected,
        onExecuteBuiltIn: _executeCourse,
        onExecuteSaved: _executeSavedCourse,
        onAddNew: _showAddFlugkursDialog,
      ),
    );
  }
  void _showVideoDialog() {
    showDialog(
      context: context,
      builder: (context) => VideoDialog(
        backendHost: backendHost,
        isConnected: isConnected,
        onExecuteBuiltIn: _executeCourse,
        onExecuteSaved: _executeSavedCourse,
        onAddNew: _showAddFlugkursDialog,
      ),
    );
  }

  void _toggleVideoRecording() {
    showDialog(
      context: context,
      builder: (context) => FlugkurseDialog(
        backendHost: backendHost,
        isConnected: isConnected,
        onExecuteBuiltIn: _executeCourse,
        onExecuteSaved: _executeSavedCourse,
        onAddNew: _showAddFlugkursDialog,
      ),
    );
  }

  Future<void> _executeSavedCourse(int courseId) async {
    Navigator.of(context).pop();

    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Nicht verbunden!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Flugkurs gestartet...'),
        backgroundColor: Colors.blue,
      ),
    );

    try {
      final res = await http.post(
        Uri.parse('http://$backendHost/flugkurs/$courseId/execute'),
        headers: {'Content-Type': 'application/json'},
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              data['success'] == true
                  ? 'Flugkurs läuft!'
                  : 'Fehler: ${data['error']}',
            ),
            backgroundColor: data['success'] == true
                ? Colors.green
                : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddFlugkursDialog() {
    showDialog(
      context: context,
      builder: (context) => AddFlugkursDialog(backendHost: backendHost),
    );
  }

  Future<void> _toggleAiVision() async {
    try {
      final res = await http.post(
        Uri.parse('http://$backendHost/detection/toggle'),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => aiVisionEnabled = data['enabled'] == true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              aiVisionEnabled
                  ? 'AI Erkennung aktiviert'
                  : 'AI Erkennung deaktiviert',
            ),
            backgroundColor:
                aiVisionEnabled ? Colors.blueAccent : Colors.grey,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      debugPrint('Fehler bei AI-Toggle: $e');
    }
  }

  Future<void> _toggleRingMode() async {
    try {
      final res = await http.post(
        Uri.parse('http://$backendHost/ring/toggle'),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true && mounted) {
        setState(() => ringModeEnabled = data['enabled'] == true);
        if (ringModeEnabled) {
          _startRingStatusPolling();
        } else {
          _stopRingStatusPolling();
          setState(() => _ringState = 'idle');
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                ringModeEnabled
                    ? 'Ring-Modus aktiviert — Drohne sucht Ringe'
                    : 'Ring-Modus deaktiviert',
              ),
              backgroundColor:
                  ringModeEnabled ? Colors.purpleAccent : Colors.grey,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Fehler bei Ring-Toggle: $e');
    }
  }

  void _startRingStatusPolling() {
    _ringStatusTimer?.cancel();
    _ringStatusTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _pollRingStatus(),
    );
  }

  void _stopRingStatusPolling() {
    _ringStatusTimer?.cancel();
    _ringStatusTimer = null;
  }

  Future<void> _pollRingStatus() async {
    try {
      final res = await http.get(Uri.parse('http://$backendHost/ring/status'));
      final data = jsonDecode(res.body);
      if (mounted) {
        setState(() => _ringState = (data['state'] as String?) ?? 'idle');
      }
    } catch (_) {}
  }

  String _ringStateLabel() {
    switch (_ringState) {
      case 'searching':
        return 'Suche Ring...';
      case 'aligning':
        return 'Ausrichten';
      case 'approaching':
        return 'Annähern';
      case 'passing':
        return 'Durchflug!';
      default:
        return 'Bereit';
    }
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!isConnected) return KeyEventResult.ignored;

    final keys = HardwareKeyboard.instance.logicalKeysPressed;

    int newA = 0, newB = 0, newC = 0, newD = 0;
    int speed = 50;
    int rotationSpeed = 100;

    if (keys.contains(LogicalKeyboardKey.keyW)) newB = speed;
    if (keys.contains(LogicalKeyboardKey.keyS)) newB = (newB == 0) ? -speed : 0;

    if (keys.contains(LogicalKeyboardKey.keyD)) newA = speed;
    if (keys.contains(LogicalKeyboardKey.keyA)) newA = (newA == 0) ? -speed : 0;

    if (keys.contains(LogicalKeyboardKey.keyI)) newC = speed;
    if (keys.contains(LogicalKeyboardKey.keyK)) newC = (newC == 0) ? -speed : 0;

    if (keys.contains(LogicalKeyboardKey.keyO) ||
        keys.contains(LogicalKeyboardKey.keyL))
      newD = rotationSpeed;
    if (keys.contains(LogicalKeyboardKey.keyJ))
      newD = (newD == 0) ? -rotationSpeed : 0;

    if (newA != _a || newB != _b || newC != _c || newD != _d) {
      if (isRecording) {
        String? newDirection = _getDirectionFromRC(newA, newB, newC, newD);
        if (_currentRecordingDirection != newDirection) {
          if (_currentRecordingDirection != null && _stepStartTime != null) {
            final seconds =
                DateTime.now().difference(_stepStartTime!).inMilliseconds /
                1000.0;
            if (seconds >= 0.2) {
              final rounded = (seconds * 10).round() / 10.0;
              _recordedSteps.add(
                FlugStep(
                  direction: _currentRecordingDirection!,
                  seconds: rounded,
                ),
              );
            }
          }
          _currentRecordingDirection = newDirection;
          _stepStartTime = newDirection != null ? DateTime.now() : null;
        }
      }

      _a = newA;
      _b = newB;
      _c = newC;
      _d = newD;
      _updateRC();
    }

    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Scaffold(
        body: Stack(
          children: [
            isConnected
                ? VideoStreamView(backendUrl: 'ws://$backendHost/video')
                : Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(color: Colors.grey[900]),
                    child: const Center(
                      child: Icon(
                        Icons.videocam_outlined,
                        size: 100,
                        color: Colors.white24,
                      ),
                    ),
                  ),

            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildTopHUD(),
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [_buildLeftTools(), _buildRightTelemetry()],
                      ),
                    ),
                    _buildBottomControls(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ); // Focus
  }

  Widget _buildTopHUD() {
    return GlassContainer(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(
                  isConnected ? Icons.wifi : Icons.wifi_off,
                  color: isConnected ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'IP Adresse',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    controller: TextEditingController(text: ipAddress),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                ElevatedButton(
                  onPressed: toggleConnection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isConnected
                        ? Colors.redAccent.withOpacity(0.8)
                        : Colors.greenAccent.withOpacity(0.8),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isConnected ? 'Trennen' : 'Verbinden'),
                ),
              ],
            ),
            const Text(
              'Drohne 1',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5,
              ),
            ),
            Row(
              children: [
                IconButton(
  icon: const Icon(Icons.lightbulb),
  color: isConnected ? Colors.greenAccent : Colors.grey,
  tooltip: 'LED Steuerung',
  onPressed: () {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: SizedBox(
          width: 350,
          child: LedMatrixControl(backendHost: backendHost),
        ),
      ),
    );
  },
),
                const SizedBox(width: 15),
                const Icon(
                  Icons.battery_charging_full,
                  color: Colors.greenAccent,
                ),
                const SizedBox(width: 5),
                Text(
                  '$batteryLevel%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeftTools() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHudButton(
          icon: isRecording ? Icons.stop_circle : Icons.fiber_manual_record,
          color: isRecording ? Colors.redAccent : Colors.white,
          label: 'Flug aufzeichnen',
          onTap: _toggleRecording,
        ),
        const SizedBox(height: 15),
        _buildHudButton(
          icon: Icons.list_alt,
          label: 'Flugkurse',
          onTap: _showFlightCoursesDialog,
        ),
        const SizedBox(height: 15),
        _buildHudButton(
          icon: Icons.person_search,
          color: aiVisionEnabled ? Colors.blueAccent : Colors.white,
          label: 'AI Erkennung',
          onTap: _toggleAiVision,
        ),
        const SizedBox(height: 15),
        _buildHudButton(
          icon: Icons.adjust,
          color: ringModeEnabled ? Colors.purpleAccent : Colors.white,
          label: 'Ring-Modus',
          onTap: _toggleRingMode,
        ),
        const SizedBox(height: 15),
        _buildHudButton(
          icon: Icons.adjust,
          color: Colors.red.shade400,
          label: 'Video-Aufnahme',
          onTap:  _showVideoDialog,
        ),
      ],
    );
  }

  Widget _buildRightTelemetry() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        GlassContainer(
          width: 200,
          height: 200,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(15.0),
            child: CustomPaint(
              painter: DroneMapPainter(
                path: _dronePath,
                droneYaw: _droneYaw,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        GlassContainer(
          width: 150, // Zurück zur normalen Breite
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Höhe: $droneHeight',
                  style: const TextStyle(color: Colors.greenAccent),
                ),
                const SizedBox(height: 5),
                Text('Speed: $droneSpeed'),
                const SizedBox(height: 5),
                Text('Zeit: $droneTime'),
                const SizedBox(height: 5),
                Text(
                  'Temp: $droneTemp',
                  style: const TextStyle(color: Colors.orangeAccent),
                ),
              ],
            ),
          ),
        ),
        if (ringModeEnabled) ...[
          const SizedBox(height: 10),
          GlassContainer(
            width: 150,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ring-Modus',
                    style: TextStyle(
                      color: Colors.purpleAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _ringStateLabel(),
                    style: TextStyle(
                      color: _ringState == 'passing'
                          ? Colors.greenAccent
                          : Colors.white,
                      fontWeight: _ringState == 'passing'
                          ? FontWeight.bold
                          : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBottomControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildJoystickPlaceholder('Höhe / Drehung'),
        Column(
          children: [
            Row(
              children: [
                ElevatedButton.icon(
                  onPressed: isConnected ? () => _sendCommand('takeoff') : null,
                  icon: const Icon(Icons.flight_takeoff),
                  label: const Text('Start'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                  ),
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  onPressed: isConnected ? () => _sendCommand('land') : null,
                  icon: const Icon(Icons.flight_land),
                  label: const Text('Landen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 15),
            InkWell(
              onTap: () => _sendCommand('emergency'),
              child: Container(
                width: 150,
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.redAccent.withOpacity(0.5),
                      blurRadius: 10,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: const Center(
                  child: Text(
                    'STOPP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        _buildJoystickPlaceholder('Bewegung'),
      ],
    );
  }

  Widget _buildHudButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color color = Colors.white,
  }) {
    return InkWell(
      onTap: onTap,
      child: GlassContainer(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(width: 8),
              Text(label, style: TextStyle(color: color, fontSize: 12)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildJoystickPlaceholder(String label) {
    return GlassContainer(
      width: 140,
      height: 140,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(0.05),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.control_camera, size: 40, color: Colors.white54),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.white54),
            ),
          ],
        ),
      ),
    );
  }
}

class DroneMapPainter extends CustomPainter {
  final List<Offset> path;
  final double droneYaw;

  DroneMapPainter({required this.path, required this.droneYaw});

  static const int _maxTrail = 1000;

  @override
  void paint(Canvas canvas, Size size) {
    _drawBackground(canvas, size);
    _drawGrid(canvas, size);

    final center = Offset(size.width / 2, size.height / 2);

    if (path.isEmpty) {
      _drawDrone(canvas, center);
      _drawNorthLabel(canvas, size);
      return;
    }

    final droneWorld = path.last;
    final scale = _computeScale(size);

    Offset toScreen(Offset world) => center + (world - droneWorld) * scale;

    final trailStart = path.length > _maxTrail ? path.length - _maxTrail : 0;
    _drawTrail(canvas, trailStart, toScreen);

    if (path.length > 1) {
      _drawStartMarker(canvas, toScreen(path.first));
    }

    _drawDrone(canvas, center);
    _drawNorthLabel(canvas, size);
  }

  double _computeScale(Size size) {
    if (path.length < 2) return 10.0;

    double minX = path[0].dx, maxX = path[0].dx;
    double minY = path[0].dy, maxY = path[0].dy;
    for (final p in path) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    final extent = math.max(maxX - minX, maxY - minY);
    if (extent < 0.5) return 10.0;
    final available = math.min(size.width, size.height) * 0.75;
    return (available / extent).clamp(2.0, 40.0);
  }

  void _drawBackground(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = const Color(0xFF060D1A),
    );
  }

  void _drawGrid(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFF112233)
      ..strokeWidth = 0.5;

    const step = 25.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final axisPaint = Paint()
      ..color = const Color(0xFF1E3A5F)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), axisPaint);
    canvas.drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), axisPaint);
  }

  void _drawTrail(Canvas canvas, int startIdx, Offset Function(Offset) toScreen) {
    final total = path.length - startIdx;
    if (total < 2) return;

    for (int i = startIdx + 1; i < path.length; i++) {
      final t = (i - startIdx) / total;
      final color = Color.lerp(
        const Color(0xFF004466).withValues(alpha: 0),
        const Color(0xFF00E5FF),
        t * t,
      )!;

      canvas.drawLine(
        toScreen(path[i - 1]),
        toScreen(path[i]),
        Paint()
          ..color = color
          ..strokeWidth = 1.5 + t * 2.0
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  void _drawStartMarker(Canvas canvas, Offset pos) {
    canvas.drawCircle(
      pos,
      7,
      Paint()
        ..color = const Color(0xFF00FF88).withValues(alpha: 0.3)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(pos, 4, Paint()..color = const Color(0xFF00FF88));
    canvas.drawCircle(
      pos,
      4,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );
  }

  void _drawDrone(Canvas canvas, Offset pos) {
    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(droneYaw * math.pi / 180.0);

    final arrowPath = Path()
      ..moveTo(0, -14)
      ..lineTo(8, 7)
      ..lineTo(0, 2)
      ..lineTo(-8, 7)
      ..close();

    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10),
    );
    canvas.drawPath(arrowPath, Paint()..color = const Color(0xFF00E5FF));
    canvas.drawPath(
      arrowPath,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    canvas.restore();
  }

  void _drawNorthLabel(Canvas canvas, Size size) {
    final tp = TextPainter(
      text: const TextSpan(
        text: 'N ↑',
        style: TextStyle(
          color: Color(0xFF3A7A9E),
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, 3));
  }

  @override
  bool shouldRepaint(covariant DroneMapPainter old) =>
      old.path.length != path.length || old.droneYaw != droneYaw;
}

