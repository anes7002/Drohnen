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
  bool _isOn = true;
  Color _selectedColor = Colors.red;
  bool _isBlinking = false;
  bool _isSending = false;

  // 8x8 Pixel-Muster (false = aus, true = an)
  List<bool> _pixelPattern = List.generate(64, (_) => false);

  void _togglePixel(int index) {
    if (!_isOn) return;
    setState(() => _pixelPattern[index] = !_pixelPattern[index]);
  }

  void _clearMatrix() {
    setState(() => _pixelPattern = List.generate(64, (_) => false));
  }

  Future<void> _applyLed() async {
    setState(() => _isSending = true);
    try {
      final r = (_selectedColor.r * 255.0).round().clamp(0, 255);
      final g = (_selectedColor.g * 255.0).round().clamp(0, 255);
      final b = (_selectedColor.b * 255.0).round().clamp(0, 255);

      await http.post(
        Uri.parse('http://${widget.backendHost}/led'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'r': _isOn ? r : 0,
          'g': _isOn ? g : 0,
          'b': _isOn ? b : 0,
          'blink': _isBlinking,
          'freq': 1.0,
        }),
      );
    } catch (e) {
      debugPrint('LED Fehler: $e');
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

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
            _buildHeader(),
            const Divider(color: Colors.white24),
            const SizedBox(height: 10),
            _buildMatrixGrid(),
            const SizedBox(height: 20),
            _buildColorPicker(),
            const SizedBox(height: 20),
            _buildEffectControls(),
            const SizedBox(height: 16),
            _buildApplyButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text(
          'LED Steuerung',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        Row(
          children: [
            const Text('An', style: TextStyle(color: Colors.white54)),
            Switch(
              value: _isOn,
              onChanged: (val) => setState(() => _isOn = val),
              activeThumbColor: Colors.greenAccent,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMatrixGrid() {
    return AspectRatio(
      aspectRatio: 1,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
        ),
        child: GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 8,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: 64,
          itemBuilder: (context, index) {
            final active = _isOn && _pixelPattern[index];
            return GestureDetector(
              onTap: () => _togglePixel(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                decoration: BoxDecoration(
                  color: active ? _selectedColor : Colors.grey[850],
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: active
                      ? [BoxShadow(color: _selectedColor.withValues(alpha: 0.5), blurRadius: 4)]
                      : [],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildColorPicker() {
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
      children: colors.map((color) {
        final selected = _selectedColor == color;
        return GestureDetector(
          onTap: () => setState(() => _selectedColor = color),
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
                  ? [BoxShadow(color: color.withValues(alpha: 0.6), blurRadius: 6)]
                  : [],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildEffectControls() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        ElevatedButton.icon(
          onPressed: _clearMatrix,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Clear'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
        ),
        FilterChip(
          label: const Text('Blinken'),
          selected: _isBlinking,
          onSelected: (val) => setState(() => _isBlinking = val),
          selectedColor: Colors.blueAccent,
          labelStyle: TextStyle(
            color: _isBlinking ? Colors.white : Colors.white70,
          ),
        ),
      ],
    );
  }

  Widget _buildApplyButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isSending ? null : _applyLed,
        icon: _isSending
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.lightbulb),
        label: Text(_isSending ? 'Wird gesendet...' : 'Anwenden'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.blueGrey[700],
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}
