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
