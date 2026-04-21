class SavedFlugkurs {
  final int id;
  final String name;
  final List<Map<String, dynamic>> commands;

  SavedFlugkurs({required this.id, required this.name, required this.commands});

  factory SavedFlugkurs.fromJson(Map<String, dynamic> json) {
    return SavedFlugkurs(
      id: json['id'] as int,
      name: json['name'] as String,
      commands: List<Map<String, dynamic>>.from(json['commands'] as List),
    );
  }
}
