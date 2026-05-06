import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/saved_flugkurs.dart';

class FlugkurseDialog extends StatefulWidget {
  final String backendHost;
  final bool isConnected;
  final Future<void> Function(List<Map<String, dynamic>>) onExecuteBuiltIn;
  final Future<void> Function(int) onExecuteSaved;
  final VoidCallback onAddNew;

  const FlugkurseDialog({
    Key? key,
    required this.backendHost,
    required this.isConnected,
    required this.onExecuteBuiltIn,
    required this.onExecuteSaved,
    required this.onAddNew,
  }) : super(key: key);

  @override
  State<FlugkurseDialog> createState() => _FlugkurseDialogState();
}

class _FlugkurseDialogState extends State<FlugkurseDialog> {
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
              const Text(
                'Vordefiniert',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              const SizedBox(height: 4),
              ListTile(
                leading: const Icon(Icons.crop_square, color: Colors.white),
                title: const Text(
                  'Viereck fliegen',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Takeoff → 4x Seiten → Land',
                  style: TextStyle(color: Colors.white54),
                ),
                onTap: () => widget.onExecuteBuiltIn([
                  {"command": "takeoff"},
                  {
                    "command": "forward",
                    "args": {"distance": 50},
                  },
                  {
                    "command": "right",
                    "args": {"distance": 50},
                  },
                  {
                    "command": "backward",
                    "args": {"distance": 50},
                  },
                  {
                    "command": "left",
                    "args": {"distance": 50},
                  },
                  {"command": "land"},
                ]),
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.swap_vert, color: Colors.white),
                title: const Text(
                  'Fahrstuhl',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Start → Hoch → Runter → Landen',
                  style: TextStyle(color: Colors.white54),
                ),
                onTap: () => widget.onExecuteBuiltIn([
                  {"command": "takeoff"},
                  {
                    "command": "up",
                    "args": {"distance": 50},
                  },
                  {
                    "command": "down",
                    "args": {"distance": 50},
                  },
                  {"command": "land"},
                ]),
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.rotate_right, color: Colors.white),
                title: const Text(
                  'Pirouette',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: const Text(
                  'Dreht sich einmal um 360°',
                  style: TextStyle(color: Colors.white54),
                ),
                onTap: () => widget.onExecuteBuiltIn([
                  {"command": "takeoff"},
                  {
                    "command": "rotate_right",
                    "args": {"angle": 360},
                  },
                  {"command": "land"},
                ]),
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white38),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Gespeicherte Kurse',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      widget.onAddNew();
                    },
                    icon: const Icon(
                      Icons.add,
                      size: 18,
                      color: Colors.blueAccent,
                    ),
                    label: const Text(
                      'Hinzufügen',
                      style: TextStyle(color: Colors.blueAccent, fontSize: 12),
                    ),
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
                  child: Text(
                    'Fehler: $_error',
                    style: const TextStyle(color: Colors.redAccent),
                  ),
                )
              else if (_savedCourses.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(8.0),
                  child: Text(
                    'Keine gespeicherten Kurse.',
                    style: TextStyle(color: Colors.white54),
                  ),
                )
              else
                ..._savedCourses.map(
                  (course) => ListTile(
                    leading: const Icon(
                      Icons.play_circle_outline,
                      color: Colors.greenAccent,
                    ),
                    title: Text(
                      course.name,
                      style: const TextStyle(color: Colors.white),
                    ),
                    subtitle: Text(
                      '${course.commands.length} Schritt(e)',
                      style: const TextStyle(color: Colors.white54),
                    ),
                    trailing: IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Colors.redAccent,
                      ),
                      onPressed: () => _deleteCourse(course.id),
                    ),
                    onTap: () => widget.onExecuteSaved(course.id),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Schließen',
            style: TextStyle(color: Colors.redAccent),
          ),
        ),
      ],
    );
  }
}
