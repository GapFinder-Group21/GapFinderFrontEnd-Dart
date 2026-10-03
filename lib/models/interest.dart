class Interest {
  // InterestBasicDTO
  final int id;
  final String name;

  Interest({
    required this.id,
    required this.name,
  });

  factory Interest.fromJson(Map<String, dynamic> json) {
    return Interest(
      id: json['id'],
      name: json['name'] ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
  };
}