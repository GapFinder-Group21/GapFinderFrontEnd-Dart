import 'user.dart';
import 'building.dart';
import '../utils/date_formatter_util.dart';

class UserLocationLog {
  final int id;
  final DateTime timestamp;

  // Solo presentes con UserLocationLogCompleteDTO
  final User? user;
  final Building? building;

  UserLocationLog({
    required this.id,
    required this.timestamp,
    this.user,
    this.building,
  });

  factory UserLocationLog.fromJson(Map<String, dynamic> json) {
    return UserLocationLog(
      id: json['id'],
      timestamp: DateFormatterUtil.parseDateTime(json['timestamp']),
      user: json['user'] != null ? User.fromJson(json['user']) : null,
      building: json['building'] != null
          ? Building.fromJson(json['building'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': DateFormatterUtil.formatDateTime(timestamp),
  };
}