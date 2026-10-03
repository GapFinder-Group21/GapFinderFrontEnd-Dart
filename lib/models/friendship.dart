import 'package:gapfinderfrontend_dart/models/user.dart';

import '../utils/date_formatter_util.dart';
import 'friendship_status_enum.dart';

class Friendship {
  // FriendshipBasicDTO
  final int id;
  final FriendshipStatusEnum status;
  final DateTime createdAt;
  final int? requesterId;
  final int? receiverId;

  // Solo presentes con FriendshipCompleteDTO
  final User? requester;
  final User? receiver;

  Friendship({
    required this.id,
    required this.status,
    required this.createdAt,
    this.requesterId,
    this.receiverId,
    this.requester,
    this.receiver,
  });

  factory Friendship.fromJson(Map<String, dynamic> json) {
    return Friendship(
      id: json['id'],
      status: FriendshipStatusEnum.fromString(json['status']),
      createdAt: DateFormatterUtil.parseDateTime(json['createdAt']),
      requesterId: json['requesterId'],
      receiverId: json['receiverId'],
      requester: json['requester'] != null
          ? User.fromJson(json['requester'])
          : null,
      receiver: json['receiver'] != null
          ? User.fromJson(json['receiver'])
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'status': status.toJson(),
    'createdAt': DateFormatterUtil.formatDateTime(createdAt),
    'requesterId': requesterId,
    'receiverId': receiverId,
  };
}