import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class LedMatrixControl extends StatefulWidget {
  final String backendHost;
  const LedMatrixControl({super.key, required this.backendHost});

  @override
  State<LedMatrixControl> createState() => _LedMatrixControlState();
}

class _LedMatrixControlState extends State<LedMatrixControl> {
  Color _primaryColor = const Color(0xFFFF0000);
  Color _secondaryColor = const Color(0xFF000000);
  bool _blinking = false;
  double _blinkFreq = 2.0;
  bool _isSending = false;
  String? _activePreset;

  static const _colorOptions = [
    Color(0xFFFF0000), // Rot
    Color(0xFFFF6600), // Orange
    Color(0xFFFFFF00), // Gelb
    Color(0xFF00FF00), // Grün
    Color(0xFF00FFFF), // Cyan
    Color(0xFF0000FF), // Blau
    Color(0xFFFF00FF), // Lila
    Color(0xFFFFFFFF), // Weiß
  ];

  static const _colorLabels = [
    'Rot', 'Orange', 'Gelb', 'Grün', 'Cyan', 'Blau', 'Lila', 'Weiß',
  ];

  // (name, farbe1, farbe2, blinken, frequenz)
  static const _presets = [
    ('Polizei', Color(0xFF0000FF), Color(0xFFFF0000), true, 4.0),
    ('Alarm',   Color(0xFFFF0000), Color(0xFF000000), true, 6.0),
    ('SOS',     Color(0xFFFF6600), Color(0xFF000000), true, 1.0),
    ('Party',   Color(0xFFFF00FF), Color(0xFF00FFFF), true, 3.0),
  ];

  Future<void> _sendLed({
    required Color c1,
    required Color c2,
    required bool blink,
    required double freq,
  }) async {
    setState(() => _isSending = true);
    try {
      int ch(double v) => (v * 255).round().clamp(0, 255);
      await http.post(
        Uri.parse('http://${widget.backendHost}/led'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'r': ch(c1.r), 'g': ch(c1.g), 'b': ch(c1.b),
          'r2': ch(c2.r), 'g2': ch(c2.g), 'b2': ch(c2.b),
          'blink': blink,
          'freq': freq,
        }),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verbindungsfehler: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  void _apply() => _sendLed(
        c1: _primaryColor,
        c2: _blinking ? _secondaryColor : const Color(0xFF000000),
        blink: _blinking,
        freq: _blinkFreq,
      );

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(
              child: Text(
                'LED Steuerung',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white24),

            _sectionLabel('Voreinstellungen'),
            const SizedBox(height: 8),
            _buildPresets(),

            const Divider(color: Colors.white24),

            _sectionLabel('Farbe'),
            const SizedBox(height: 8),
            _buildColorPicker(
              selected: _primaryColor,
              onSelect: (c) {
                setState(() {
                  _primaryColor = c;
                  _activePreset = null;
                });
                _apply();
              },
            ),

            const Divider(color: Colors.white24),

            _buildBlinkSection(),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSending ? null : _apply,
                    icon: _isSending
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.lightbulb),
                    label: const Text('Anwenden'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[700],
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _isSending
                      ? null
                      : () {
                          setState(() {
                            _blinking = false;
                            _activePreset = 'Aus';
                          });
                          _sendLed(
                            c1: const Color(0xFF000000),
                            c2: const Color(0xFF000000),
                            blink: false,
                            freq: 1.0,
                          );
                        },
                  icon: const Icon(Icons.power_settings_new),
                  label: const Text('Aus'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: const TextStyle(color: Colors.white54, fontSize: 12),
      );

  Widget _buildPresets() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _presets.map((p) {
        final isActive = _activePreset == p.$1;
        final c1 = p.$2;
        final c2 = p.$3;
        return GestureDetector(
          onTap: () {
            setState(() {
              _primaryColor = c1;
              _secondaryColor = c2;
              _blinking = p.$4;
              _blinkFreq = p.$5;
              _activePreset = p.$1;
            });
            _sendLed(c1: c1, c2: c2, blink: p.$4, freq: p.$5);
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? c1.withValues(alpha: 0.2) : Colors.black26,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isActive ? c1 : Colors.white24,
                width: isActive ? 2 : 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _dot(c1),
                const SizedBox(width: 3),
                _dot(c2 == const Color(0xFF000000) ? Colors.white24 : c2),
                const SizedBox(width: 6),
                Text(
                  p.$1,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight:
                        isActive ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _dot(Color c) => Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle),
      );

  Widget _buildColorPicker({
    required Color selected,
    required ValueChanged<Color> onSelect,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(_colorOptions.length, (i) {
        final c = _colorOptions[i];
        final isSelected = selected == c;
        return Tooltip(
          message: _colorLabels[i],
          child: GestureDetector(
            onTap: () => onSelect(c),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: isSelected
                    ? [BoxShadow(color: c.withValues(alpha: 0.7), blurRadius: 8)]
                    : null,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildBlinkSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _sectionLabel('Blinken'),
            Transform.scale(
              scale: 0.85,
              child: Switch(
                value: _blinking,
                onChanged: (v) {
                  setState(() {
                    _blinking = v;
                    _activePreset = null;
                  });
                  _apply();
                },
                activeThumbColor: Colors.amber,
              ),
            ),
          ],
        ),
        if (_blinking) ...[
          const SizedBox(height: 8),
          _sectionLabel('Zweite Farbe'),
          const SizedBox(height: 6),
          _buildColorPicker(
            selected: _secondaryColor,
            onSelect: (c) {
              setState(() {
                _secondaryColor = c;
                _activePreset = null;
              });
              _apply();
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _sectionLabel('${_blinkFreq.toStringAsFixed(1)} Hz  '),
              Expanded(
                child: Slider(
                  value: _blinkFreq,
                  min: 0.5,
                  max: 10.0,
                  divisions: 19,
                  activeColor: Colors.amber,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(() => _blinkFreq = v),
                  onChangeEnd: (_) => _apply(),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
