class DroneItem {
  final int id;
  final String name;
  final String ip;
  final String? mac;
  final String? addedAt;

  DroneItem({
    required this.id,
    required this.name,
    required this.ip,
    this.mac,
    this.addedAt,
  });

  factory DroneItem.fromJson(Map<String, dynamic> json) {
    return DroneItem(
      id: json['id'],
      name: json['name'],
      ip: json['ip_adresse'],
      mac: json['mac_adresse'],
      addedAt: json['erstellt_am'],
    );
  }
}
