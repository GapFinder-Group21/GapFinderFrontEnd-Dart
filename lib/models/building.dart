class Building {
  // BuildingBasicDTO
  final int id;
  final String name;
  final double latitude;
  final double longitude;
  final double radiusMeters;

  Building({
    required this.id,
    required this.name,
    this.latitude = 0,
    this.longitude = 0,
    this.radiusMeters = 0,
  });

  // Some buildings are split in numbered parts ("Bobo 1", "Bobo 2") for the GPS; the user sees one
  // building without the number. Same rule as the back uses in its stats.
  static String baseName(String name) => name.replaceFirst(RegExp(r'\s+\d+$'), '');

  // Name shown to the user ("Bobo", not "Bobo 2")
  String get displayName => baseName(name);

  // One building per base name (its first part), in the same order
  static List<Building> mergeParts(List<Building> buildings) {
    final seen = <String>{};
    return buildings.where((b) => seen.add(b.displayName)).toList();
  }

  factory Building.fromJson(Map<String, dynamic> json) {
    return Building(
      id: json['id'],
      name: json['name'] ?? '',
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0,
      radiusMeters: (json['radiusMeters'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'latitude': latitude,
    'longitude': longitude,
    'radiusMeters': radiusMeters,
  };
}
