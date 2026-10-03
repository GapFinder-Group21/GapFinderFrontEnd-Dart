import 'building.dart';
import 'interest.dart';
import 'effort_type_enum.dart';
import '../utils/date_formatter_util.dart';

class User {
  // UserBasicDTO
  final int id;
  final String name;
  final String email;
  final String? phoneNumber;
  final String career;
  final int? semester;
  final String? avatarUrl;
  final bool verified;
  final DateTime? createdAt;
  final EffortTypeEnum? preferredEffort;
  final DateTime? locationUpdatedAt;

  // Solo presentes con UserCompleteDTO
  final List<Interest> interests;
  final Building? currentBuilding;

  User({
    required this.id,
    required this.name,
    required this.email,
    this.phoneNumber,
    required this.career,
    this.semester,
    this.avatarUrl,
    this.verified = false,
    this.createdAt,
    this.preferredEffort,
    this.locationUpdatedAt,
    this.interests = const [],
    this.currentBuilding,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phoneNumber'],
      career: json['career'] ?? '',
      semester: json['semester'] ?? 0,
      avatarUrl: json['avatarUrl'],
      verified: json['verified'] ?? false,
      createdAt: json['createdAt'] != null
          ? DateFormatterUtil.parseDateTime(json['createdAt'])
          : null,
      preferredEffort: json['preferredEffort'] != null
          ? EffortTypeEnum.fromString(json['preferredEffort'])
          : null,
      locationUpdatedAt: json['locationUpdatedAt'] != null
          ? DateFormatterUtil.parseDateTime(json['locationUpdatedAt'])
          : null,
      interests: (json['interests'] as List?)
          ?.map((i) => Interest.fromJson(i))
          .toList() ??
          [],
      currentBuilding: json['currentBuilding'] != null
          ? Building.fromJson(json['currentBuilding'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'email': email,
    'phoneNumber': phoneNumber,
    'career': career,
    'semester': semester,
    'avatarUrl': avatarUrl,
    'verified': verified,
    'preferredEffort': preferredEffort?.name.toUpperCase(),
    'locationUpdatedAt': locationUpdatedAt != null
        ? DateFormatterUtil.formatDateTime(locationUpdatedAt!)
        : null,
  };
}
