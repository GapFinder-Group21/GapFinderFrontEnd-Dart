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
