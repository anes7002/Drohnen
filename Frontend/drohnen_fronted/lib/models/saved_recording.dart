class SavedRecording {
  final int id;
  final String filename;
  final String? createdAt;

  SavedRecording({required this.id, required this.filename, this.createdAt});

  factory SavedRecording.fromJson(Map<String, dynamic> json) {
    return SavedRecording(
      id: json['id'] as int,
      filename: json['filename'] as String,
      createdAt: json['created_at'] as String?,
    );
  }
}
