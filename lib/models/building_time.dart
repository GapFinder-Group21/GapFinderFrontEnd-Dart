import 'building.dart';

class BuildingTime {
  final Building building;
  final int minutes;

  BuildingTime({required this.building, required this.minutes});

  factory BuildingTime.fromJson(Map<String, dynamic> json) {
    return BuildingTime(
      building: Building.fromJson(json['building']),
      minutes: json['minutes'],
    );
  }
}
