import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// Editor für die 8x8-LED-Matrix der Tello Talent.
///
/// Jedes Pixel kann auf Aus/Rot/Blau/Lila gesetzt werden; das Muster wird als
/// 64-Zeichen-String ('0','r','b','p') an `POST /mled` ({"leds": ...}) geschickt.
class LedMatrixGrid extends StatefulWidget {
  final String backendHost;
  const LedMatrixGrid({super.key, required this.backendHost});

  @override
  State<LedMatrixGrid> createState() => _LedMatrixGridState();
}

class _LedMatrixGridState extends State<LedMatrixGrid> {
  // 64 Pixel, zeilenweise von oben links. '0'=aus, 'r'=rot, 'b'=blau, 'p'=lila.
  final List<String> _cells = List.filled(64, '0');
  String _paint = 'r'; // aktuell gewählte "Pinsel"-Farbe
  bool _busy = false;

  static const Map<String, Color> _palette = {
    '0': Color(0xFF2A2A2A), // aus
    'r': Color(0xFFFF3030), // rot
    'b': Color(0xFF3A6BFF), // blau
    'p': Color(0xFFB44CFF), // lila
  };
  static const Map<String, String> _labels = {
    '0': 'Aus', 'r': 'Rot', 'b': 'Blau', 'p': 'Lila',
  };

  String get _pattern => _cells.join();

  /// Schickt das aktuelle Muster an die Drohne (fire-and-forget bei Tippen).
  Future<void> _send({bool feedback = false}) async {
    if (feedback) setState(() => _busy = true);
    try {
      await http.post(
        Uri.parse('http://${widget.backendHost}/mled'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'leds': _pattern}),
      );
    } catch (e) {
      if (mounted && feedback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verbindungsfehler: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted && feedback) setState(() => _busy = false);
    }
  }

  void _paintCell(int i) {
    if (_cells[i] == _paint) return;
    setState(() => _cells[i] = _paint);
    _send(); // live anzeigen
  }

  void _setAll(String c) {
    setState(() {
      for (var i = 0; i < _cells.length; i++) {
        _cells[i] = c;
      }
    });
    _send();
  }

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
                '8×8 Matrix-Muster',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const Divider(color: Colors.white24),

            const Text('Farbe (Pinsel)',
                style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _palette.keys.map((k) {
                final selected = _paint == k;
                return GestureDetector(
                  onTap: () => setState(() => _paint = k),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: _palette[k],
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected ? Colors.white : Colors.white12,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: Text(
                      _labels[k]!,
                      style: TextStyle(
                        color: k == '0' ? Colors.white60 : Colors.white,
                        fontSize: 13,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),

            const SizedBox(height: 14),

            // 8x8 Raster
            AspectRatio(
              aspectRatio: 1,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: GridView.builder(
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 3,
                    crossAxisSpacing: 3,
                  ),
                  itemCount: 64,
                  itemBuilder: (context, i) {
                    final on = _cells[i] != '0';
                    return GestureDetector(
                      onTap: () => _paintCell(i),
                      child: Container(
                        decoration: BoxDecoration(
                          color: _palette[_cells[i]],
                          borderRadius: BorderRadius.circular(3),
                          boxShadow: on
                              ? [
                                  BoxShadow(
                                    color: _palette[_cells[i]]!
                                        .withValues(alpha: 0.7),
                                    blurRadius: 4,
                                  )
                                ]
                              : null,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 12),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : () => _send(feedback: true),
                    icon: _busy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send),
                    label: const Text('Senden'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blueGrey[700],
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _busy ? null : () => _setAll(_paint),
                  icon: const Icon(Icons.format_color_fill),
                  tooltip: 'Alles füllen',
                  color: Colors.white,
                  style: IconButton.styleFrom(backgroundColor: Colors.grey[800]),
                ),
                const SizedBox(width: 4),
                IconButton(
                  onPressed: _busy ? null : () => _setAll('0'),
                  icon: const Icon(Icons.clear),
                  tooltip: 'Alles aus',
                  color: Colors.white,
                  style: IconButton.styleFrom(backgroundColor: Colors.grey[800]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
