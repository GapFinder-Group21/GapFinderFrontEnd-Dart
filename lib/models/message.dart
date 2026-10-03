import 'user.dart';
import 'match.dart';
import 'open_table.dart';
import '../utils/date_formatter_util.dart';

class Message {
  final int id;
  final String content;
  final DateTime sentAt;
  final String senderName;

  // Relaciones opcionales (presentes cuando viene el CompleteDTO)
  final User? sender;
  final Match? match;
  final OpenTable? openTable;

  Message({
    required this.id,
    required this.content,
    required this.sentAt,
    required this.senderName,
    this.sender,
    this.match,
    this.openTable,
  });

  factory Message.fromJson(Map json) {
    return Message(
      id: json['id'],
      content: json['content'] ?? '',
      sentAt: DateFormatterUtil.parseDateTime(json['sentAt']),
      senderName: json['senderName'] ?? '',
      sender: json['sender'] != null ? User.fromJson(json['sender']) : null,
      match: json['match'] != null ? Match.fromJson(json['match']) : null,
      openTable: json['openTable'] != null
          ? OpenTable.fromJson(json['openTable'])
          : null,
    );
  }

  Map toJson() {
    return {
      'id': id,
      'content': content,
      'sentAt': DateFormatterUtil.formatDateTime(sentAt),
      'senderName': senderName,
      'sender': sender?.toJson(),
      'match': match?.toJson(),
      'openTable': openTable?.toJson(),
    };
  }
}