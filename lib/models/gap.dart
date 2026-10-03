import 'user.dart';
import '../utils/date_formatter_util.dart';

class Gap {
  // GapBasicDTO
  final int id;
  final DateTime startTime;
  final DateTime endTime;
  final int? userId;

  // Solo presente con GapCompleteDTO (por ejemplo, en candidates y pendientes de match)
  final User? user;

  Gap({
    required this.id,
    required this.startTime,
    required this.endTime,
    this.userId,
    this.user,
  });

  int get durationMinutes => endTime.difference(startTime).inMinutes;

  factory Gap.fromJson(Map<String, dynamic> json) {
    return Gap(
      id: json['id'],
      startTime: DateFormatterUtil.parseDateTime(json['startTime']),
      endTime: DateFormatterUtil.parseDateTime(json['endTime']),
      userId: json['userId'],
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': DateFormatterUtil.formatDateTime(startTime),
    'endTime': DateFormatterUtil.formatDateTime(endTime),
    'userId': userId,
  };
}