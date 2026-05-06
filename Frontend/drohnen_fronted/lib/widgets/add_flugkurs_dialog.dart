import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/flug_step.dart';

class AddFlugkursDialog extends StatefulWidget {
  final String backendHost;

  const AddFlugkursDialog({Key? key, required this.backendHost})
    : super(key: key);

  @override
  State<AddFlugkursDialog> createState() => _AddFlugkursDialogState();
}

class _AddFlugkursDialogState extends State<AddFlugkursDialog> {
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
          _steps.add(FlugStep(direction: _activeDirection!, seconds: rounded));
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
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    if (_steps.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mindestens einen Schritt aufzeichnen!'),
          backgroundColor: Colors.orange,
        ),
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
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Fehler: ${data['error']}'),
              backgroundColor: Colors.red,
            ),
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
            Icon(
              icon,
              color: isActive ? Colors.white : Colors.white70,
              size: 28,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                color: isActive ? Colors.white : Colors.white54,
              ),
            ),
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
          Text('Flugkurs aufzeichnen', style: TextStyle(color: Colors.white)),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Name des Flugkurses',
                labelStyle: const TextStyle(color: Colors.white54),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
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
                    _dirButton(
                      'rotate_left',
                      Icons.rotate_left,
                      'Links\ndrehen',
                    ),
                    const SizedBox(width: 8),
                    _dirButton('forward', Icons.arrow_upward, 'Vor'),
                    const SizedBox(width: 8),
                    _dirButton(
                      'rotate_right',
                      Icons.rotate_right,
                      'Rechts\ndrehen',
                    ),
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
            Container(
              height: 140,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
              ),
              child: _steps.isEmpty
                  ? const Center(
                      child: Text(
                        'Noch keine Schritte aufgezeichnet.',
                        style: TextStyle(color: Colors.white38),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _steps.length,
                      itemBuilder: (context, index) => ListTile(
                        dense: true,
                        leading: Text(
                          '${index + 1}.',
                          style: const TextStyle(color: Colors.white54),
                        ),
                        title: Text(
                          _steps[index].label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.redAccent,
                            size: 18,
                          ),
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
                  child: const Text(
                    'Alle löschen',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Abbrechen',
            style: TextStyle(color: Colors.white54),
          ),
        ),
        ElevatedButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blueAccent,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}
