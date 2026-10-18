import 'open_table.dart';
import 'user.dart';
import '../utils/date_formatter_util.dart';

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
}
