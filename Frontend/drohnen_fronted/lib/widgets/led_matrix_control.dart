import 'package:flutter/material.dart';

class LedMatrixControl extends StatefulWidget {
  const LedMatrixControl({Key? key}) : super(key: key);

  @override
  State<LedMatrixControl> createState() => _LedMatrixControlState();
}

class _LedMatrixControlState extends State<LedMatrixControl> {
  // Status-Variablen
  bool _isOn = true;
  Color _selectedColor = Colors.red;
  bool _isBlinking = false;
  
  // Das 8x8 Pixel-Muster (false = aus, true = an mit _selectedColor)
  List<bool> _pixelPattern = List.generate(64, (index) => false);

  void _togglePixel(int index) {
    if (!_isOn) return;
    setState(() {
      _pixelPattern[index] = !_pixelPattern[index];
    });
  }

  void _clearMatrix() {
    setState(() {
      _pixelPattern = List.generate(64, (index) => false);
    });
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
          ],
        ),
      ),
    );
  }

  // --- UI Komponenten ---

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        const Text("LED Matrix Control", 
          style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
        Switch(
          value: _isOn,
          onChanged: (val) => setState(() => _isOn = val),
          activeColor: Colors.blue,
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
            return GestureDetector(
              onTap: () => _togglePixel(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: _isOn && _pixelPattern[index] ? _selectedColor : Colors.grey[850],
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: _isOn && _pixelPattern[index] 
                    ? [BoxShadow(color: _selectedColor.withOpacity(0.5), blurRadius: 4)] 
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
    List<Color> colors = [Colors.red, Colors.green, Colors.blue, Colors.yellow, Colors.purple, Colors.orange];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: colors.map((color) {
        return GestureDetector(
          onTap: () => setState(() => _selectedColor = color),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: _selectedColor == color ? Colors.white : Colors.transparent,
                width: 2,
              ),
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
          icon: const Icon(Icons.refresh),
          label: const Text("Clear"),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
        ),
        FilterChip(
          label: const Text("Blinken"),
          selected: _isBlinking,
          onSelected: (val) => setState(() => _isBlinking = val),
          selectedColor: Colors.blue,
        ),
      ],
    );
  }
}