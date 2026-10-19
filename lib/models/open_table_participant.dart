import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/core/utils/date_formatter_util.dart';

class OpenTableParticipant {
  // OpenTableParticipantBasicDTO
  final int id;
  final DateTime joinedAt;
  final int? openTableId;
  final int? userId;

  // OpenTableParticipantCompleteDTO
  final OpenTable? openTable;
  final User? user;

  OpenTableParticipant({
    required this.id,
    required this.joinedAt,
    this.openTableId,
    this.userId,
    this.openTable,
    this.user,
  });

  factory OpenTableParticipant.fromJson(Map<String, dynamic> json) {
    final openTable = json['openTable'] != null
        ? OpenTable.fromJson(json['openTable'])
        : null;
    final user = json['user'] != null ? User.fromJson(json['user']) : null;

    return OpenTableParticipant(
      id: json['id'],
      joinedAt: DateFormatterUtil.parseDateTime(json['joinedAt']),
      // El id plano viene en OpenTableParticipantBasicDTO; si solo llega el objeto, se toma de ahí
      openTableId: json['openTableId'] ?? openTable?.id,
      userId: json['userId'] ?? user?.id,
      openTable: openTable,
      user: user,
    );
  }

  // El back toma openTableId y userId planos (POST/PUT /open-table-participants)
  Map<String, dynamic> toJson() => {
    'id': id,
    'joinedAt': DateFormatterUtil.formatDateTime(joinedAt),
    if (openTableId != null) 'openTableId': openTableId,
    if (userId != null) 'userId': userId,
  };

  // Copy for the local cache: it keeps the user so the participants list can be drawn again
  Map<String, dynamic> toCacheJson() => {
    ...toJson(),
    if (user != null)
      'user': {
        ...user!.toJson(),
        'interests': user!.interests.map((i) => i.toJson()).toList(),
      },
  };
}
