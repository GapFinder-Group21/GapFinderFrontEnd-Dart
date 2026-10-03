import 'notification_type_enum.dart';
import 'user.dart';
import '../utils/date_formatter_util.dart';

class AppNotification {
  // NotificationBasicDTO
  final int id;
  final NotificationTypeEnum type;
  final String message;
  final int? relatedEntityId;
  final bool read;
  final DateTime createdAt;

  // Solo presente con NotificationCompleteDTO
  final User? recipient;

  AppNotification({
    required this.id,
    required this.type,
    required this.message,
    this.relatedEntityId,
    required this.read,
    required this.createdAt,
    this.recipient,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'],
      type: NotificationTypeEnum.fromString(json['type']),
      message: json['message'] ?? '',
      relatedEntityId: json['relatedEntityId'],
      read: json['read'] ?? false,
      createdAt: DateFormatterUtil.parseDateTime(json['createdAt']),
      recipient: json['recipient'] != null
          ? User.fromJson(json['recipient'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.toJson(),
    'message': message,
    'relatedEntityId': relatedEntityId,
    'read': read,
    'createdAt': DateFormatterUtil.formatDateTime(createdAt),
  };
}