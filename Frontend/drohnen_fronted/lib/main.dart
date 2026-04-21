import 'dart:async';
import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
 
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Erzwinge Querformat für die Drohnen-Steuerung
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeRight,
    DeviceOrientation.landscapeLeft,
  ]).then((_) {
    runApp(const RoboMasterApp());
  });
}
 
class RoboMasterApp extends StatelessWidget {
  const RoboMasterApp({Key? key}) : super(key: key);
 
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RoboMaster TT Control',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.black,
        fontFamily: 'Roboto',
      ),
      home: const IpEntryScreen(),
    );
  }
}
 
// ==========================================
// Hilfsklasse für die Drohnen-Daten
// ==========================================
class DroneItem {
  final String name;
  final String ip;

  DroneItem({required this.name, required this.ip});
}

// ==========================================
// Modell für gespeicherte Flugkurse
// ==========================================
class SavedFlugkurs {
  final int id;
  final String name;
  final List<Map<String, dynamic>> commands;

  SavedFlugkurs({required this.id, required this.name, required this.commands});

  factory SavedFlugkurs.fromJson(Map<String, dynamic> json) {
    return SavedFlugkurs(
      id: json['id'] as int,
      name: json['name'] as String,
      commands: List<Map<String, dynamic>>.from(json['commands'] as List),
    );
  }
}

// ==========================================
// Modell für einen aufgezeichneten Schritt
// ==========================================
class FlugStep {
  final String direction;
  final double seconds;

  FlugStep({required this.direction, required this.seconds});

  Map<String, dynamic> toJson() => {'direction': direction, 'seconds': seconds};

  static const _labels = {
    'forward': 'Vorwärts',
    'backward': 'Rückwärts',
    'left': 'Links',
    'right': 'Rechts',
    'up': 'Hoch',
    'down': 'Runter',
    'rotate_left': 'Links drehen',
    'rotate_right': 'Rechts drehen',
    'takeoff': 'Start',
    'land': 'Landen',
  };

  String get label {
    if (direction == 'takeoff' || direction == 'land') {
      return _labels[direction] ?? direction;
    }
    return '${_labels[direction] ?? direction}: ${seconds.toStringAsFixed(1)} s';
  }
}
 
// ==========================================
// Bildschirm für die IP-Eingabe (Start)
// ==========================================
class IpEntryScreen extends StatefulWidget {
  const IpEntryScreen({Key? key}) : super(key: key);
 
  @override
  State<IpEntryScreen> createState() => _IpEntryScreenState();
}
 
class _IpEntryScreenState extends State<IpEntryScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ipController = TextEditingController(text: '172.20.10.2');
 
  // Unsere Liste für die Drohnen
  List<DroneItem> _droneList = [];
 
  // Die aktuell ausgewählte Drohne
  DroneItem? _selectedDrone;
 
  void _addDroneToList() {
    final name = _nameController.text.trim();
    final ip = _ipController.text.trim();
 
    if (name.isNotEmpty && ip.isNotEmpty) {
      setState(() {
        _droneList.add(DroneItem(name: name, ip: ip));
        // Felder leeren für die nächste Eingabe (optional, IP bleibt bei dir vielleicht oft gleich,
        // aber wir löschen hier mal den Namen)
        _nameController.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bitte Name und IP-Adresse eingeben!'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
 
  void _connectToDrone() {
    if (_selectedDrone == null) return;
 
    // Gehe zum nächsten Fenster und übergebe die IP der AUSGEWÄHLTEN Drohne
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => DroneDashboard(initialIp: _selectedDrone!.ip),
      ),
    );
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.black, Colors.grey[900]!, Colors.blueGrey[900]!],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: GlassContainer(
              // Box breiter gemacht, um Liste und Eingabe nebeneinander zu zeigen
              width: 650,
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.flight_takeoff, size: 40, color: Colors.blueAccent),
                    const SizedBox(height: 10),
                    const Text(
                      'LAGA-Drohnenmanager',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                   
                    // Layout aufgeteilt in Links (Eingabe) und Rechts (Liste)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // LINKE SEITE: Eingabefelder
                        Expanded(
                          flex: 1,
                          child: Column(
                            children: [
                              TextField(
                                controller: _nameController,
                                decoration: InputDecoration(
                                  labelText: 'Drohnen-Name',
                                  prefixIcon: const Icon(Icons.label),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  filled: true,
                                  fillColor: Colors.black26,
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 15),
                              TextField(
                                controller: _ipController,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: InputDecoration(
                                  labelText: 'IP-Adresse',
                                  prefixIcon: const Icon(Icons.wifi),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  filled: true,
                                  fillColor: Colors.black26,
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 15),
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _addDroneToList,
                                  icon: const Icon(Icons.add),
                                  label: const Text('ZUR LISTE HINZUFÜGEN'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blueGrey,
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                       
                        const SizedBox(width: 20),
                       
                        // RECHTE SEITE: Die Liste
                        Expanded(
                          flex: 1,
                          child: Container(
                            height: 190, // Feste Höhe für die Liste
                            decoration: BoxDecoration(
                              color: Colors.black26,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: _droneList.isEmpty
                                ? const Center(
                                    child: Text(
                                      'Noch keine Drohnen hinzugefügt.',
                                      style: TextStyle(color: Colors.white54),
                                    ),
                                  )
                                : ListView.builder(
                                    itemCount: _droneList.length,
                                    itemBuilder: (context, index) {
                                      final drone = _droneList[index];
                                      final isSelected = drone == _selectedDrone;
 
                                      return ListTile(
                                        leading: Icon(
                                          Icons.airplanemode_active,
                                          color: isSelected ? Colors.white : Colors.blueAccent,
                                        ),
                                        title: Text(drone.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                        subtitle: Text(drone.ip),
                                        selected: isSelected,
                                        selectedTileColor: Colors.blueAccent.withOpacity(0.5),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        onTap: () {
                                          setState(() {
                                            _selectedDrone = drone;
                                          });
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                   
                    const SizedBox(height: 25),
                   
                    // BOTTOM: Weiter-Button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        // Button ist nur klickbar, wenn eine Drohne ausgewählt wurde!
                        onPressed: _selectedDrone == null ? null : _connectToDrone,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent,
                          disabledBackgroundColor: Colors.blueAccent.withOpacity(0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          _selectedDrone == null
                              ? 'BITTE DROHNE AUSWÄHLEN'
                              : 'VERBINDEN MIT "${_selectedDrone!.name.toUpperCase()}"',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
 
// ==========================================
// DAS DASHBOARD (HUD)
// ==========================================
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

  final String backendHost = '127.0.0.1:8000'; // Bei Android Emulator ggf. auf 10.0.2.2:8000 ändern
  WebSocketChannel? _rcChannel;
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
        setState(() {
          isConnected = false;
          batteryLevel = '---';
          droneHeight = '---';
          droneSpeed = '---';
          droneTime = '---';
          droneTemp = '---';
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
          _rcChannel = WebSocketChannel.connect(Uri.parse('ws://$backendHost/rc'));
          _rcChannel!.stream.listen((message) {
            final msgData = jsonDecode(message);
            if (msgData['type'] == 'telemetry') {
              final tele = msgData['data'];
              if (mounted) {
                setState(() {
                  batteryLevel = (tele['battery']?.toString() ?? '---').replaceAll('%', '');
                  droneHeight = tele['height']?.toString() ?? '---';
                  droneSpeed = tele['speed']?.toString() ?? '---';
                  droneTime = tele['flight_time']?.toString() ?? '---';
                  droneTemp = tele['temp']?.toString() ?? '---';
                });
              }
            }
          });
          if (mounted) {
            setState(() {
              isConnected = true;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Verbunden!'), backgroundColor: Colors.green),
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
            final seconds = DateTime.now().difference(_stepStartTime!).inMilliseconds / 1000.0;
            if (seconds >= 0.2) {
              final rounded = (seconds * 10).round() / 10.0;
              _recordedSteps.add(FlugStep(direction: _currentRecordingDirection!, seconds: rounded));
            }
          }
          _currentRecordingDirection = null;
          _stepStartTime = null;
          
          _recordedSteps.add(FlugStep(direction: command, seconds: 5.0)); // Fake duration
        }
      }
      _rcChannel!.sink.add(jsonEncode({"command": command}));
    }
  }

  @override
  void dispose() {
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
        const SnackBar(content: Text('Nicht verbunden!'), backgroundColor: Colors.red),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Flugkurs gestartet...'), backgroundColor: Colors.blue),
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
        await Future.delayed(Duration(seconds: 1));
      } catch (e) {
        debugPrint('Fehler bei Flugkurs-Befehl: $e');
      }
    }

    if (mounted && isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Flugkurs beendet!'), backgroundColor: Colors.green),
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
      _stepStartTime = _currentRecordingDirection != null ? DateTime.now() : null;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aufzeichnung gestartet!'), backgroundColor: Colors.blue),
      );
    } else {
      // Finish recording the last step if any
      if (_currentRecordingDirection != null && _stepStartTime != null) {
        final seconds = DateTime.now().difference(_stepStartTime!).inMilliseconds / 1000.0;
        if (seconds >= 0.2) {
          final rounded = (seconds * 10).round() / 10.0;
          _recordedSteps.add(FlugStep(direction: _currentRecordingDirection!, seconds: rounded));
        }
      }
      _currentRecordingDirection = null;
      _stepStartTime = null;

      if (_recordedSteps.isNotEmpty) {
        _showSaveCourseDialog();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Keine Schritte aufgezeichnet.'), backgroundColor: Colors.orange),
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
              title: const Text('Flugkurs speichern', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${_recordedSteps.length} Schritte aufgezeichnet.', style: const TextStyle(color: Colors.white54)),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Name',
                      labelStyle: const TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.black26,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
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
                  child: const Text('Verwerfen', style: TextStyle(color: Colors.redAccent)),
                ),
                ElevatedButton(
                  onPressed: saving ? null : () async {
                    final name = nameController.text.trim();
                    if (name.isEmpty) return;
                    setStateDialog(() => saving = true);
                    try {
                      final res = await http.post(
                        Uri.parse('http://$backendHost/flugkurs'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'name': name,
                          'commands': _recordedSteps.map((s) => s.toJson()).toList(),
                        }),
                      );
                      final data = jsonDecode(res.body);
                      if (data['success'] == true) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Kurs gespeichert!'), backgroundColor: Colors.green),
                        );
                        _recordedSteps.clear();
                      } else {
                        throw Exception(data['error']);
                      }
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                      );
                      setStateDialog(() => saving = false);
                    }
                  },
                  child: saving ? const CircularProgressIndicator() : const Text('Speichern'),
                )
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
      builder: (context) => _FlugkurseDialog(
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
        const SnackBar(content: Text('Nicht verbunden!'), backgroundColor: Colors.red),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Flugkurs gestartet...'), backgroundColor: Colors.blue),
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
            content: Text(data['success'] == true ? 'Flugkurs läuft!' : 'Fehler: ${data['error']}'),
            backgroundColor: data['success'] == true ? Colors.green : Colors.red,
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
      builder: (context) => _AddFlugkursDialog(backendHost: backendHost),
    );
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

    if (keys.contains(LogicalKeyboardKey.keyO) || keys.contains(LogicalKeyboardKey.keyL)) newD = rotationSpeed;
    if (keys.contains(LogicalKeyboardKey.keyJ)) newD = (newD == 0) ? -rotationSpeed : 0;

    if (newA != _a || newB != _b || newC != _c || newD != _d) {
      if (isRecording) {
        String? newDirection = _getDirectionFromRC(newA, newB, newC, newD);
        if (_currentRecordingDirection != newDirection) {
          if (_currentRecordingDirection != null && _stepStartTime != null) {
            final seconds = DateTime.now().difference(_stepStartTime!).inMilliseconds / 1000.0;
            if (seconds >= 0.2) {
              final rounded = (seconds * 10).round() / 10.0;
              _recordedSteps.add(FlugStep(direction: _currentRecordingDirection!, seconds: rounded));
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
          Container(
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey[900]
            ),
            child: const Center(
              child: Icon(Icons.videocam_outlined, size: 100, color: Colors.white24),
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
                      children: [
                        _buildLeftTools(),
                        _buildRightTelemetry(),
                      ],
                    ),
                  ),
                  _buildBottomControls(),
                ],
              ),
            ),
          ),
        ],
      ),
    )); // Focus
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
                    backgroundColor: isConnected ? Colors.redAccent.withOpacity(0.8) : Colors.greenAccent.withOpacity(0.8),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(isConnected ? 'Trennen' : 'Verbinden'),
                ),
              ],
            ),
            const Text(
              'Drohne 1',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.lightbulb),
                  color: isConnected ? Colors.greenAccent : Colors.grey,
                  tooltip: 'LED Steuerung',
                  onPressed: () {},
                ),
                const SizedBox(width: 15),
                const Icon(Icons.battery_charging_full, color: Colors.greenAccent),
                const SizedBox(width: 5),
                Text('$batteryLevel%', style: const TextStyle(fontWeight: FontWeight.bold)),
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
          onTap: () => setState(() => aiVisionEnabled = !aiVisionEnabled),
        ),
        const SizedBox(height: 15),
        _buildHudButton(
          icon: Icons.adjust,
          color: ringModeEnabled ? Colors.purpleAccent : Colors.white,
          label: 'Ring-Modus',
          onTap: () => setState(() => ringModeEnabled = !ringModeEnabled),
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
          width: 150,
          height: 120,
          child: Stack(
            children: [
              const Center(child: Icon(Icons.map_outlined, color: Colors.white54, size: 40)),
              Positioned(
                top: 50,
                left: 70,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(color: Colors.blueAccent, shape: BoxShape.circle),
                ),
              )
            ],
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
                Text('Höhe: $droneHeight', style: const TextStyle(color: Colors.greenAccent)),
                const SizedBox(height: 5),
                Text('Speed: $droneSpeed'),
                const SizedBox(height: 5),
                Text('Zeit: $droneTime'),
                const SizedBox(height: 5),
                Text('Temp: $droneTemp', style: const TextStyle(color: Colors.orangeAccent)),
              ],
            ),
          ),
        ),
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
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
                ),
                const SizedBox(width: 20),
                ElevatedButton.icon(
                  onPressed: isConnected ? () => _sendCommand('land') : null,
                  icon: const Icon(Icons.flight_land),
                  label: const Text('Landen'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blueGrey),
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
                    BoxShadow(color: Colors.redAccent.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)
                  ],
                ),
                child: const Center(
                  child: Text(
                    'STOPP',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
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
 
  Widget _buildHudButton({required IconData icon, required String label, required VoidCallback onTap, Color color = Colors.white}) {
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
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}
 
class GlassContainer extends StatelessWidget {
  final Widget child;
  final double? width;
  final double? height;
  final BoxDecoration? decoration;

  const GlassContainer({Key? key, required this.child, this.width, this.height, this.decoration}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(15.0),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
        child: Container(
          width: width,
          height: height,
          decoration: decoration ?? BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(15.0),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ==========================================
// Dialog: Flugkurse anzeigen (inkl. gespeicherter)
// ==========================================
class _FlugkurseDialog extends StatefulWidget {
  final String backendHost;
  final bool isConnected;
  final Future<void> Function(List<Map<String, dynamic>>) onExecuteBuiltIn;
  final Future<void> Function(int) onExecuteSaved;
  final VoidCallback onAddNew;

  const _FlugkurseDialog({
    required this.backendHost,
    required this.isConnected,
    required this.onExecuteBuiltIn,
    required this.onExecuteSaved,
    required this.onAddNew,
  });

  @override
  State<_FlugkurseDialog> createState() => _FlugkurseDialogState();
}

class _FlugkurseDialogState extends State<_FlugkurseDialog> {
  List<SavedFlugkurs> _savedCourses = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCourses();
  }

  Future<void> _loadCourses() async {
    try {
      final res = await http.get(
        Uri.parse('http://${widget.backendHost}/flugkurs'),
      );
      final data = jsonDecode(res.body);
      if (data['success'] == true) {
        final list = (data['data'] as List)
            .map((e) => SavedFlugkurs.fromJson(e as Map<String, dynamic>))
            .toList();
        if (mounted) {
          setState(() {
            _savedCourses = list;
            _loading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _error = data['error'] as String?;
            _loading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Verbindungsfehler';
          _loading = false;
        });
      }
    }
  }

  Future<void> _deleteCourse(int id) async {
    try {
      await http.delete(Uri.parse('http://${widget.backendHost}/flugkurs/$id'));
      await _loadCourses();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fehler beim Löschen des Flugkurses'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: const Row(
        children: [
          Icon(Icons.route, color: Colors.blueAccent),
          SizedBox(width: 10),
          Text('Flugkurse', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- Vordefinierte Kurse ---
              const Text('Vordefiniert',
                  style: TextStyle(color: Colors.white54, fontSize: 12)),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.crop_square, color: Colors.white),
                title: const Text('Viereck fliegen',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Takeoff → 4x Seiten → Land',
                    style: TextStyle(color: Colors.white54)),
                onTap: () => widget.onExecuteBuiltIn([
                  {"command": "takeoff"},
                  {"command": "forward", "args": {"distance": 50}},
                  {"command": "right", "args": {"distance": 50}},
                  {"command": "backward", "args": {"distance": 50}},
                  {"command": "left", "args": {"distance": 50}},
                  {"command": "land"},
                ]),
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.swap_vert, color: Colors.white),
                title: const Text('Fahrstuhl',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Start → Hoch → Runter → Landen',
                    style: TextStyle(color: Colors.white54)),
                onTap: () => widget.onExecuteBuiltIn([
                  {"command": "takeoff"},
                  {"command": "up", "args": {"distance": 50}},
                  {"command": "down", "args": {"distance": 50}},
                  {"command": "land"},
                ]),
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.rotate_right, color: Colors.white),
                title: const Text('Pirouette',
                    style: TextStyle(color: Colors.white)),
                subtitle: const Text('Dreht sich einmal um 360°',
                    style: TextStyle(color: Colors.white54)),
                onTap: () => widget.onExecuteBuiltIn([
                  {"command": "takeoff"},
                  {"command": "rotate_right", "args": {"angle": 360}},
                  {"command": "land"},
                ]),
              ),
              const SizedBox(height: 16),
              // --- Gespeicherte Kurse ---
              const Divider(color: Colors.white38),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Gespeicherte Kurse',
                      style: TextStyle(color: Colors.white54, fontSize: 12)),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onAddNew();
                    },
                    icon: const Icon(Icons.add, size: 18, color: Colors.blueAccent),
                    label: const Text('Hinzufügen',
                        style: TextStyle(color: Colors.blueAccent, fontSize: 12)),
                  ),
                ],
              ),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text('Fehler: $_error',
                      style: const TextStyle(color: Colors.redAccent)),
                )
              else if (_savedCourses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text('Keine gespeicherten Kurse.',
                      style: TextStyle(color: Colors.white54)),
                )
              else
                ..._savedCourses.map((course) => ListTile(
                      leading: const Icon(Icons.play_circle_outline,
                          color: Colors.greenAccent),
                      title: Text(course.name,
                          style: const TextStyle(color: Colors.white)),
                      subtitle: Text(
                          '${course.commands.length} Schritt(e)',
                          style: const TextStyle(color: Colors.white54)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.redAccent),
                        onPressed: () => _deleteCourse(course.id),
                      ),
                      onTap: () => widget.onExecuteSaved(course.id),
                    )),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Schließen',
              style: TextStyle(color: Colors.redAccent)),
        ),
      ],
    );
  }
}

// ==========================================
// Dialog: Neuen Flugkurs aufzeichnen
// ==========================================
class _AddFlugkursDialog extends StatefulWidget {
  final String backendHost;

  const _AddFlugkursDialog({required this.backendHost});

  @override
  State<_AddFlugkursDialog> createState() => _AddFlugkursDialogState();
}

class _AddFlugkursDialogState extends State<_AddFlugkursDialog> {
  static const double _minStepDuration = 0.2; // seconds

  final TextEditingController _nameController = TextEditingController();
  final List<FlugStep> _steps = [];
  bool _saving = false;

  DateTime? _pressStart;
  String? _activeDirection;

  void _onPressStart(String direction) {
    _pressStart = DateTime.now();
    _activeDirection = direction;
    setState(() {});
  }

  void _onPressEnd() {
    if (_pressStart != null && _activeDirection != null) {
      final seconds =
          DateTime.now().difference(_pressStart!).inMilliseconds / 1000.0;
      if (seconds >= _minStepDuration) {
        final rounded = (seconds * 10).round() / 10.0;
        setState(() {
          _steps.add(FlugStep(
            direction: _activeDirection!,
            seconds: rounded,
          ));
        });
      }
    }
    _pressStart = null;
    _activeDirection = null;
    setState(() {});
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Bitte einen Namen eingeben!'),
            backgroundColor: Colors.orange),
      );
      return;
    }
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Mindestens einen Schritt aufzeichnen!'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await http.post(
        Uri.parse('http://${widget.backendHost}/flugkurs'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'name': name,
          'commands': _steps.map((s) => s.toJson()).toList(),
        }),
      );
      final data = jsonDecode(res.body);
      if (mounted) {
        if (data['success'] == true) {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Flugkurs gespeichert!'),
                backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text('Fehler: ${data['error']}'),
                backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dirButton(String direction, IconData icon, String label) {
    final isActive = _activeDirection == direction;
    return GestureDetector(
      onTapDown: (_) => _onPressStart(direction),
      onTapUp: (_) => _onPressEnd(),
      onTapCancel: () => _onPressEnd(),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 72,
        height: 72,
        decoration: BoxDecoration(
          color: isActive
              ? Colors.blueAccent.withOpacity(0.8)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isActive ? Colors.blueAccent : Colors.white24,
            width: isActive ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: isActive ? Colors.white : Colors.white70, size: 28),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    fontSize: 10,
                    color: isActive ? Colors.white : Colors.white54)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.grey[900],
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: const Row(
        children: [
          Icon(Icons.fiber_manual_record, color: Colors.redAccent),
          SizedBox(width: 10),
          Text('Flugkurs aufzeichnen',
              style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Name field
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Name des Flugkurses',
                labelStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10)),
                filled: true,
                fillColor: Colors.black26,
                isDense: true,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Taste gedrückt halten = Richtung aufnehmen',
              style: TextStyle(color: Colors.white54, fontSize: 12),
            ),
            const SizedBox(height: 12),
            // Direction buttons – 3×3 grid (empty center)
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _dirButton('rotate_left', Icons.rotate_left, 'Links\ndrehen'),
                    const SizedBox(width: 8),
                    _dirButton('forward', Icons.arrow_upward, 'Vor'),
                    const SizedBox(width: 8),
                    _dirButton('rotate_right', Icons.rotate_right, 'Rechts\ndrehen'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _dirButton('left', Icons.arrow_back, 'Links'),
                    const SizedBox(width: 8),
                    _dirButton('up', Icons.arrow_upward_rounded, 'Hoch'),
                    const SizedBox(width: 8),
                    _dirButton('right', Icons.arrow_forward, 'Rechts'),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(width: 80),
                    _dirButton('backward', Icons.arrow_downward, 'Zurück'),
                    const SizedBox(width: 8),
                    _dirButton('down', Icons.arrow_downward_rounded, 'Runter'),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Recorded steps list
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: _steps.isEmpty
                  ? const Center(
                      child: Text('Noch keine Schritte aufgezeichnet.',
                          style: TextStyle(color: Colors.white38)))
                  : ListView.builder(
                      itemCount: _steps.length,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        leading: Text('${index + 1}.',
                            style: const TextStyle(color: Colors.white54)),
                        title: Text(_steps[index].label,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 13)),
                        trailing: IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.redAccent, size: 18),
                          onPressed: () =>
                              setState(() => _steps.removeAt(index)),
                        ),
                      ),
                    ),
            ),
            if (_steps.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() => _steps.clear()),
                  child: const Text('Alle löschen',
                      style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Abbrechen',
              style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.save),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueAccent,
              foregroundColor: Colors.white),
        ),
      ],
    );
  }
}