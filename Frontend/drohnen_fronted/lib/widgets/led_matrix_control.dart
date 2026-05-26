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
  // ── Status-LED ──────────────────────────────────────────────────────────
  bool _ledOn = true;
  Color _selectedColor = Colors.red;
  bool _isBlinking = false;
  bool _isSendingLed = false;

  // ── Matrix-Display ───────────────────────────────────────────────────────
  // Each cell: '0'=aus, 'r'=rot, 'b'=blau, 'p'=lila
  List<String> _pixels = _ttPattern.split('');
  String _paintColor = 'r';
  bool _isSendingMatrix = false;

  bool _matrixOn = true;
  bool _matrixBlinking = false;
  double _matrixBlinkFreq = 2.0;

  // ── Scroll-Text ──────────────────────────────────────────────────────────
  final TextEditingController _scrollTextCtrl = TextEditingController();
  String _scrollDirection = 'l';
  String _scrollColor = 'b';
  double _scrollSpeed = 1.5;
  bool _isSendingScroll = false;

  static const _ttPattern =
      '00rrrr000r0000r0r0r00r0rr000000rr0r00r0rr00rr00r0r0000r000rrrr00';

  // Reihenfolge für Farb-Rotation der gesamten Matrix
  static const _colorCycle = ['r', 'b', 'p'];

  @override
  void initState() {
    super.initState();
    _loadPattern();
  }

  @override
  void dispose() {
    _scrollTextCtrl.dispose();
    super.dispose();
  }

  // ── Matrix helpers ───────────────────────────────────────────────────────

  Future<void> _loadPattern() async {
    try {
      final res = await http
          .get(Uri.parse('http://${widget.backendHost}/mled/pattern'))
          .timeout(const Duration(seconds: 3));
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['success'] == true && mounted) {
        final raw =
            (body['pattern'] as String).padRight(64, '0').substring(0, 64);
        setState(() {
          _pixels = raw.split('');
          _matrixOn = body['on'] as bool? ?? true;
          _matrixBlinking = body['blinking'] as bool? ?? false;
        });
      }
    } catch (_) {
      // Backend nicht erreichbar — TT-Startmuster bleibt sichtbar
    }
  }

  void _paintPixel(int index) {
    if (!_matrixOn) return;
    setState(() => _pixels[index] = _paintColor);
  }

  void _clearMatrix() {
    setState(() => _pixels = List.generate(64, (_) => '0'));
  }

  void _loadTtPattern() {
    setState(() => _pixels = _ttPattern.split(''));
  }

  /// Rotiert alle eingefärbten Pixel durch die Farb-Reihenfolge r→b→p→r.
  void _cycleMatrixColor() {
    setState(() {
      _pixels = _pixels.map((c) {
        if (c == '0') return '0';
        final i = _colorCycle.indexOf(c);
        if (i < 0) return c;
        return _colorCycle[(i + 1) % _colorCycle.length];
      }).toList();
    });
  }

  Future<void> _applyMatrix() async {
    setState(() => _isSendingMatrix = true);
    try {
      final res = await http.post(
        Uri.parse('http://${widget.backendHost}/mled'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'pattern': _pixels.join()}),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted) {
        if (body['success'] == true) {
          _snack('Muster gesendet!', isError: false);
        } else {
          _snack('Fehler: ${body['error'] ?? 'Unbekannt'}');
        }
      }
    } catch (e) {
      if (mounted) _snack('Verbindungsfehler: $e');
    } finally {
      if (mounted) setState(() => _isSendingMatrix = false);
    }
  }

  Future<void> _toggleMatrixVisibility(bool on) async {
    setState(() {
      _matrixOn = on;
      if (!on) _matrixBlinking = false;
    });
    try {
      await http.post(
        Uri.parse('http://${widget.backendHost}/mled/visibility'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'on': on}),
      );
    } catch (e) {
      if (mounted) _snack('Verbindungsfehler: $e');
    }
  }

  Future<void> _toggleMatrixBlink(bool enabled) async {
    setState(() => _matrixBlinking = enabled);
    try {
      await http.post(
        Uri.parse('http://${widget.backendHost}/mled/blink'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'enabled': enabled, 'freq': _matrixBlinkFreq}),
      );
    } catch (e) {
      if (mounted) _snack('Verbindungsfehler: $e');
    }
  }

  Future<void> _sendScrollText() async {
    final text = _scrollTextCtrl.text.trim();
    if (text.isEmpty) {
      _snack('Bitte Text eingeben');
      return;
    }
    setState(() => _isSendingScroll = true);
    try {
      final res = await http.post(
        Uri.parse('http://${widget.backendHost}/mled/scroll'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'text': text,
          'direction': _scrollDirection,
          'color': _scrollColor,
          'freq': _scrollSpeed,
        }),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted) {
        if (body['success'] == true) {
          setState(() => _matrixBlinking = false);
          _snack('Text wird gescrollt!', isError: false);
        } else {
          _snack('Fehler: ${body['error'] ?? 'Unbekannt'}');
        }
      }
    } catch (e) {
      if (mounted) _snack('Verbindungsfehler: $e');
    } finally {
      if (mounted) setState(() => _isSendingScroll = false);
    }
  }

  // ── Status-LED helpers ────────────────────────────────────────────────────

  Future<void> _applyLed({bool? isOn}) async {
    final on = isOn ?? _ledOn;
    setState(() => _isSendingLed = true);
    try {
      final r = (_selectedColor.r * 255.0).round().clamp(0, 255);
      final g = (_selectedColor.g * 255.0).round().clamp(0, 255);
      final b = (_selectedColor.b * 255.0).round().clamp(0, 255);

      final res = await http.post(
        Uri.parse('http://${widget.backendHost}/led'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'r': on ? r : 0,
          'g': on ? g : 0,
          'b': on ? b : 0,
          'blink': _isBlinking,
          'freq': 1.0,
        }),
      );
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (mounted && body['success'] != true) {
        _snack('LED Fehler: ${body['error'] ?? 'Unbekannt'}');
      }
    } catch (e) {
      if (mounted) _snack('Verbindungsfehler: $e');
    } finally {
      if (mounted) setState(() => _isSendingLed = false);
    }
  }

  void _snack(String msg, {bool isError = true}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red[700] : Colors.green[700],
      duration: Duration(seconds: isError ? 4 : 2),
    ));
  }

  // ── Color mapping ─────────────────────────────────────────────────────────

  Color _pixelColor(String c) {
    switch (c) {
      case 'r':
        return Colors.red;
      case 'b':
        return Colors.blue;
      case 'p':
        return Colors.purple;
      default:
        return const Color(0xFF1C1C1C);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.grey[900],
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('LED Steuerung',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            const Divider(color: Colors.white24),

            // ── Matrix section ─────────────────────────────────────────────
            _sectionHeader(
              'Matrix-Anzeige (8×8)',
              switchValue: _matrixOn,
              onSwitch: _toggleMatrixVisibility,
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: _matrixOn ? 1.0 : 0.35,
              child: IgnorePointer(
                ignoring: !_matrixOn,
                child: Column(
                  children: [
                    _buildMatrixGrid(),
                    const SizedBox(height: 10),
                    _buildMatrixPalette(),
                    const SizedBox(height: 8),
                    _buildMatrixActions(),
                    const SizedBox(height: 8),
                    _buildBlinkControls(),
                  ],
                ),
              ),
            ),

            const Divider(color: Colors.white24),

            // ── Scroll-Text section ────────────────────────────────────────
            _sectionLabel('Scroll-Text'),
            const SizedBox(height: 8),
            _buildScrollControls(),

            const Divider(color: Colors.white24),

            // ── Status-LED section ─────────────────────────────────────────
            _sectionHeader(
              'Status-LED',
              switchValue: _ledOn,
              onSwitch: (val) {
                setState(() => _ledOn = val);
                _applyLed(isOn: val);
              },
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: _ledOn ? 1.0 : 0.35,
              child: IgnorePointer(
                ignoring: !_ledOn,
                child: Column(
                  children: [
                    _buildLedColorPicker(),
                    const SizedBox(height: 10),
                    _buildBlinkChip(),
                    const SizedBox(height: 12),
                    _buildLedApplyButton(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Align(
        alignment: Alignment.centerLeft,
        child: Text(text,
            style: const TextStyle(color: Colors.white54, fontSize: 12)),
      );

  Widget _sectionHeader(
    String text, {
    required bool switchValue,
    required ValueChanged<bool> onSwitch,
  }) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(text,
              style: const TextStyle(color: Colors.white54, fontSize: 12)),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: switchValue,
              onChanged: onSwitch,
              activeThumbColor: Colors.greenAccent,
            ),
          ),
        ],
      );

  Widget _buildMatrixGrid() {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final totalSize = constraints.maxWidth;
          const pad = 6.0;

          void paintAt(Offset pos) {
            final inner = totalSize - pad * 2;
            if (inner <= 0) return;
            final x = (pos.dx - pad).clamp(0.0, inner - 1);
            final y = (pos.dy - pad).clamp(0.0, inner - 1);
            final col = (x / inner * 8).floor().clamp(0, 7);
            final row = (y / inner * 8).floor().clamp(0, 7);
            _paintPixel(row * 8 + col);
          }

          return GestureDetector(
            onTapDown: (d) => paintAt(d.localPosition),
            onPanUpdate: (d) => paintAt(d.localPosition),
            child: Container(
              padding: const EdgeInsets.all(pad),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(8),
              ),
              child: GridView.builder(
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 8,
                  mainAxisSpacing: 3,
                  crossAxisSpacing: 3,
                ),
                itemCount: 64,
                itemBuilder: (_, i) {
                  final color = _pixelColor(_pixels[i]);
                  final active = _pixels[i] != '0';
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 80),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                  color: color.withValues(alpha: 0.7),
                                  blurRadius: 5)
                            ]
                          : null,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMatrixPalette() {
    final options = [
      ('0', const Color(0xFF1C1C1C), 'Aus'),
      ('r', Colors.red, 'Rot'),
      ('b', Colors.blue, 'Blau'),
      ('p', Colors.purple, 'Lila'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: options.map((opt) {
        final selected = _paintColor == opt.$1;
        return GestureDetector(
          onTap: () => setState(() => _paintColor = opt.$1),
          child: Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: opt.$2,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? Colors.white : Colors.white24,
                    width: selected ? 2.5 : 1,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                              color: opt.$2.withValues(alpha: 0.6),
                              blurRadius: 8)
                        ]
                      : null,
                ),
              ),
              const SizedBox(height: 3),
              Text(opt.$3,
                  style: TextStyle(
                      color: selected ? Colors.white : Colors.white38,
                      fontSize: 10)),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildMatrixActions() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _actionBtn(
                label: 'Robomaster',
                icon: Icons.restore,
                color: Colors.blueGrey[700]!,
                onPressed: _loadTtPattern,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _actionBtn(
                label: 'Farbe',
                icon: Icons.color_lens_outlined,
                color: Colors.teal[700]!,
                onPressed: _cycleMatrixColor,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: _actionBtn(
                label: 'Löschen',
                icon: Icons.delete_outline,
                color: Colors.redAccent,
                onPressed: _clearMatrix,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: _actionBtn(
            label: _isSendingMatrix ? 'Wird gesendet...' : 'Senden',
            icon: Icons.send,
            color: Colors.deepPurple,
            onPressed: _isSendingMatrix ? null : _applyMatrix,
          ),
        ),
      ],
    );
  }

  Widget _buildBlinkControls() {
    return Row(
      children: [
        FilterChip(
          label: const Text('Blinken'),
          avatar: Icon(
            _matrixBlinking ? Icons.flash_on : Icons.flash_off,
            size: 16,
            color: _matrixBlinking ? Colors.white : Colors.white54,
          ),
          selected: _matrixBlinking,
          onSelected: _toggleMatrixBlink,
          selectedColor: Colors.amber[700],
          labelStyle: TextStyle(
              color: _matrixBlinking ? Colors.white : Colors.white70),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Frequenz: ${_matrixBlinkFreq.toStringAsFixed(1)} Hz',
                  style:
                      const TextStyle(color: Colors.white54, fontSize: 11)),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 2,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                ),
                child: Slider(
                  value: _matrixBlinkFreq,
                  min: 0.5,
                  max: 5.0,
                  divisions: 9,
                  activeColor: Colors.amber,
                  inactiveColor: Colors.white24,
                  onChanged: (v) => setState(() => _matrixBlinkFreq = v),
                  onChangeEnd: (_) {
                    if (_matrixBlinking) _toggleMatrixBlink(true);
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScrollControls() {
    final dirs = [
      ('l', Icons.arrow_back, 'Links'),
      ('r', Icons.arrow_forward, 'Rechts'),
      ('u', Icons.arrow_upward, 'Hoch'),
      ('d', Icons.arrow_downward, 'Runter'),
    ];
    final colors = [
      ('r', Colors.red),
      ('b', Colors.blue),
      ('p', Colors.purple),
    ];

    return Column(
      children: [
        TextField(
          controller: _scrollTextCtrl,
          maxLength: 70,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText: 'Text z.B. HELLO',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: Colors.black26,
            counterStyle: const TextStyle(color: Colors.white24, fontSize: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: dirs.map((d) {
            final selected = _scrollDirection == d.$1;
            return GestureDetector(
              onTap: () => setState(() => _scrollDirection = d.$1),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: selected ? Colors.deepPurple : Colors.black26,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color:
                          selected ? Colors.white : Colors.white12),
                ),
                child: Icon(d.$2,
                    size: 18,
                    color: selected ? Colors.white : Colors.white54),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ...colors.map((c) {
              final selected = _scrollColor == c.$1;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () => setState(() => _scrollColor = c.$1),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: c.$2,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: selected ? Colors.white : Colors.transparent,
                        width: 2,
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                  color: c.$2.withValues(alpha: 0.6),
                                  blurRadius: 6)
                            ]
                          : null,
                    ),
                  ),
                ),
              );
            }),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Speed: ${_scrollSpeed.toStringAsFixed(1)}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 11)),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 2,
                      thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 7),
                    ),
                    child: Slider(
                      value: _scrollSpeed,
                      min: 0.1,
                      max: 2.5,
                      divisions: 24,
                      activeColor: Colors.deepPurpleAccent,
                      inactiveColor: Colors.white24,
                      onChanged: (v) => setState(() => _scrollSpeed = v),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _isSendingScroll ? null : _sendScrollText,
            icon: _isSendingScroll
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.text_fields, size: 16),
            label: Text(_isSendingScroll ? 'Wird gesendet...' : 'Text scrollen',
                style: const TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.indigo[600],
              padding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
        ),
      ],
    );
  }

  Widget _actionBtn({
    required String label,
    required IconData icon,
    required Color color,
    VoidCallback? onPressed,
  }) =>
      ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
      );

  Widget _buildLedColorPicker() {
    final colors = [
      Colors.red,
      Colors.green,
      Colors.blue,
      Colors.yellow,
      Colors.purple,
      Colors.orange,
      Colors.white,
      Colors.cyan,
    ];
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      runSpacing: 6,
      children: colors.map((color) {
        final selected = _selectedColor == color;
        return GestureDetector(
          onTap: () {
            setState(() => _selectedColor = color);
            _applyLed();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected ? Colors.white : Colors.transparent,
                width: 2.5,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                          color: color.withValues(alpha: 0.6), blurRadius: 6)
                    ]
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBlinkChip() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        FilterChip(
          label: const Text('Blinken'),
          selected: _isBlinking,
          onSelected: (val) {
            setState(() => _isBlinking = val);
            _applyLed();
          },
          selectedColor: Colors.blueAccent,
          labelStyle:
              TextStyle(color: _isBlinking ? Colors.white : Colors.white70),
        ),
      ],
    );
  }

  Widget _buildLedApplyButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSendingLed ? null : _applyLed,
        icon: _isSendingLed
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.lightbulb_outline),
        label: Text(_isSendingLed ? 'Wird gesendet...' : 'LED Anwenden'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueGrey[700],
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
