import 'open_table.dart';
import 'user.dart';
import '../utils/date_formatter_util.dart';

class OpenTableParticipant {
  // OpenTableParticipantBasicDTO
  final int id;
  final DateTime joinedAt;

  // OpenTableParticipantCompleteDTO
  final OpenTable? openTable;
  final User? user;

  OpenTableParticipant({
    required this.id,
    required this.joinedAt,
    this.openTable,
    this.user,
  });

  factory OpenTableParticipant.fromJson(Map<String, dynamic> json) {
    return OpenTableParticipant(
      id: json['id'],
      joinedAt: DateFormatterUtil.parseDateTime(json['joinedAt']),
      openTable: json['openTable'] != null
          ? OpenTable.fromJson(json['openTable'])
          : null,
      user: json['user'] != null ? User.fromJson(json['user']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'joinedAt': DateFormatterUtil.formatDateTime(joinedAt),
  };
}