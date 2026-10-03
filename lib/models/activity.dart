import 'effort_type_enum.dart';
import 'interest.dart';

class Activity {
  // ActivityBasicDTO
  final int id;
  final String name;
  final int durationMinutes;
  final EffortTypeEnum effortType;

  // Solo presente con ActivityCompleteDTO
  final Interest? interest;

  Activity({
    required this.id,
    required this.name,
    required this.durationMinutes,
    required this.effortType,
    this.interest,
  });

  factory Activity.fromJson(Map<String, dynamic> json) {
    return Activity(
      id: json['id'],
      name: json['name'] ?? '',
      durationMinutes: json['durationMinutes'] ?? 0,
      effortType: EffortTypeEnum.fromString(json['effortType']),
      interest: json['interest'] != null
          ? Interest.fromJson(json['interest'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'durationMinutes': durationMinutes,
    'effortType': effortType.toJson(),
  };
}