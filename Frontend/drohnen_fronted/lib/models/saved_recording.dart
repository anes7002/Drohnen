class SavedRecording {
  final int id;
  final int droneId;
  final String name;
  final String timestamp;
  final String directory;

  SavedRecording({required this.id, required this.droneId, required this.name, required this.timestamp, required this.directory});

  factory SavedRecording.fromJson(Map<String, dynamic> json) {
    return SavedRecording(
      id: json['id'] as int,
      droneId: json['drone_id'] as int,
      name: json['name'] as String,
      timestamp: json['timestamp'] as String,
      directory: json['directory'] as String,
    );
  }
}