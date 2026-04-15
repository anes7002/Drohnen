import 'dart:ui';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'dart:typed_data';

 
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
// Bildschirm für die IP-Eingabe (Start)
// ==========================================
class IpEntryScreen extends StatefulWidget {
  const IpEntryScreen({Key? key}) : super(key: key);
 
  @override
  State<IpEntryScreen> createState() => _IpEntryScreenState();
}
 
class _IpEntryScreenState extends State<IpEntryScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _ipController = TextEditingController(text: '192.168.10.1');
 
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
  WebSocketChannel? _videoChannel;
  Uint8List? _frame;
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

  // RC Control State
  final FocusNode _focusNode = FocusNode();
  final Set<LogicalKeyboardKey> _pressedKeys = {};
  int _a = 0, _b = 0, _c = 0, _d = 0;
 
  @override
  void initState() {
    super.initState();
    ipAddress = widget.initialIp;

    _videoChannel = WebSocketChannel.connect(
      Uri.parse('ws://$backendHost/video'),
      );

    _videoChannel!.stream.listen((data) {
     setState(() {
    _frame = base64Decode(data);
      } );
    });
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
      _rcChannel!.sink.add(jsonEncode({"command": command}));
    }
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _rcChannel?.sink.close();
    super.dispose();
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
        int delaySeconds = (cmd['command'] == 'takeoff' || cmd['command'] == 'land') ? 5 : 4;
        await Future.delayed(Duration(seconds: delaySeconds));
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

  void _showFlightCoursesDialog() {
    showDialog(
      context: context,
      builder: (context) {
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
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.crop_square, color: Colors.white),
                  title: const Text('Viereck fliegen', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Takeoff -> 4x Seiten -> Land', style: TextStyle(color: Colors.white54)),
                  onTap: () => _executeCourse([
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
                  title: const Text('Fahrstuhl', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Start -> Hoch -> Runter -> Landen', style: TextStyle(color: Colors.white54)),
                  onTap: () => _executeCourse([
                    {"command": "takeoff"},
                    {"command": "up", "args": {"distance": 50}},
                    {"command": "down", "args": {"distance": 50}},
                    {"command": "land"},
                  ]),
                ),
                const Divider(color: Colors.white24),
                ListTile(
                  leading: const Icon(Icons.rotate_right, color: Colors.white),
                  title: const Text('Pirouette', style: TextStyle(color: Colors.white)),
                  subtitle: const Text('Dreht sich einmal um 360°', style: TextStyle(color: Colors.white54)),
                  onTap: () => _executeCourse([
                    {"command": "takeoff"},
                    {"command": "rotate_right", "args": {"angle": 360}},
                    {"command": "land"},
                  ]),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Schließen', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!isConnected) return KeyEventResult.ignored;

    if (event is KeyDownEvent) {
      _pressedKeys.add(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _pressedKeys.remove(event.logicalKey);
    } else {
      return KeyEventResult.ignored;
    }

    int newA = 0, newB = 0, newC = 0, newD = 0;
    int speed = 100;

    if (_pressedKeys.contains(LogicalKeyboardKey.keyW)) newB = speed;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyS)) newB = (newB == 0) ? -speed : 0;

    if (_pressedKeys.contains(LogicalKeyboardKey.keyD)) newA = speed;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyA)) newA = (newA == 0) ? -speed : 0;

    if (_pressedKeys.contains(LogicalKeyboardKey.keyI)) newC = speed;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyK)) newC = (newC == 0) ? -speed : 0;

    if (_pressedKeys.contains(LogicalKeyboardKey.keyO) || _pressedKeys.contains(LogicalKeyboardKey.keyL)) newD = speed;
    if (_pressedKeys.contains(LogicalKeyboardKey.keyJ)) newD = (newD == 0) ? -speed : 0;

    if (newA != _a || newB != _b || newC != _c || newD != _d) {
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
            // 1. EBENE: DER VIDEO-HINTERGRUND (FPV Layer)
            Container(
              width: double.infinity,
              height: double.infinity,
              decoration: const BoxDecoration(color: Colors.black),
              child: _frame != null
                  ? Image.memory(
                      _frame!,
                      gaplessPlayback: true, // Verhindert das Flackern beim Frame-Wechsel
                      fit: BoxFit.cover,     // Füllt den ganzen Bildschirm aus
                    )
                  : const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.blueAccent),
                          SizedBox(height: 15),
                          Text(
                            "Warte auf Video-Stream...",
                            style: TextStyle(color: Colors.white54, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
            ),

            // 2. EBENE: DEIN HUD (Interface Layer oben drüber)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Obere HUD-Leiste (Batterie, Signal)
                    _buildTopHUD(),

                    // Mittlerer Teil (Steuerungs-Symbole/Telemetrie)
                    Expanded(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildLeftTools(),
                          _buildRightTelemetry(),
                        ],
                      ),
                    ),

                    // Untere Steuerung (Buttons)
                    _buildBottomControls(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
          onTap: () => setState(() => isRecording = !isRecording),
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
          onTap: () async {
          final newState = !aiVisionEnabled;

          setState(() => aiVisionEnabled = newState);

          await http.post(
            Uri.parse('http://$backendHost/vision/toggle_ai'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'enabled': newState}),
          );
        },
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
          width: 150,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Höhe: $droneHeight', style: const TextStyle(color: Colors.greenAccent)),
                const SizedBox(height: 5),
                Text('Speed: $droneSpeed'),
                const SizedBox(height: 5),
                Text('Distanz: ---'), // Distance ist in der aktuellen Telemetrie nicht direkt verfügbar
                const SizedBox(height: 5),
                Text('Zeit: $droneTime'),
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