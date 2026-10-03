import 'open_table_status_enum.dart';
import 'user.dart';
import 'building.dart';
import 'activity.dart';
import '../utils/date_formatter_util.dart';

class OpenTable {
  // OpenTableBasicDTO
  final int id;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final int maxParticipants;
  final OpenTableStatusEnum status;
  final DateTime? createdAt;
  final Activity? activity;

  // Solo presentes con OpenTableCompleteDTO
  final User? creator;
  final Building? building;

  OpenTable({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    required this.maxParticipants,
    required this.status,
    this.createdAt,
    this.activity,
    this.creator,
    this.building,
  });

  factory OpenTable.fromJson(Map<String, dynamic> json) {
    return OpenTable(
      id: json['id'],
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      startTime: DateFormatterUtil.parseDateTime(json['startTime']),
      endTime: DateFormatterUtil.parseDateTime(json['endTime']),
      maxParticipants: json['maxParticipants'] ?? 0,
      status: OpenTableStatusEnum.fromString(json['status']),
      createdAt: json['createdAt'] != null
          ? DateFormatterUtil.parseDateTime(json['createdAt'])
          : null,
      activity: json['activity'] != null
          ? Activity.fromJson(json['activity'])
          : null,
      creator: json['creator'] != null
          ? User.fromJson(json['creator'])
          : null,
      building: json['building'] != null
          ? Building.fromJson(json['building'])
          : null,
    );
  }

  // createdAt no se manda: la columna es updatable = false
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'description': description,
    'startTime': DateFormatterUtil.formatDateTime(startTime),
    'endTime': DateFormatterUtil.formatDateTime(endTime),
    'maxParticipants': maxParticipants,
    'status': status.toJson(),
    if (activity != null) 'activity': {'id': activity!.id},
  };
}