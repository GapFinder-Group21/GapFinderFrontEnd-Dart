import 'package:gapfinderfrontend_dart/core/utils/date_formatter_util.dart';

// sent: the back has it · pending: waiting to be sent · failed: the back refused it
enum ChatMessageStatus { sent, pending, failed }

// One chat message between the user and a friend (ChatMessageDTO + local status)
class ChatMessage {
  // Id made by the app (UUID): the same message is never stored twice
  final String clientId;
  // Id given by the back; null while it was not sent
  final int? serverId;
  final int senderId;
  final int receiverId;
  final String content;
  final DateTime createdAt;
  final ChatMessageStatus status;

  const ChatMessage({
    required this.clientId,
    this.serverId,
    required this.senderId,
    required this.receiverId,
    required this.content,
    required this.createdAt,
    this.status = ChatMessageStatus.sent,
  });

  bool isMine(int userId) => senderId == userId;

  // A message from the back is always sent
  factory ChatMessage.fromServer(Map<String, dynamic> json) {
    return ChatMessage(
      clientId: json['clientId'] as String,
      serverId: (json['id'] as num?)?.toInt(),
      senderId: (json['senderId'] as num).toInt(),
      receiverId: (json['receiverId'] as num).toInt(),
      content: json['content'] as String? ?? '',
      createdAt: DateFormatterUtil.parseDateTime(json['createdAt'] as String),
    );
  }

  // Simple map, used to move messages to the isolate and back
  Map<String, dynamic> toMap() => {
        'clientId': clientId,
        'serverId': serverId,
        'senderId': senderId,
        'receiverId': receiverId,
        'content': content,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
      };

  factory ChatMessage.fromMap(Map<String, dynamic> map) {
    return ChatMessage(
      clientId: map['clientId'] as String,
      serverId: (map['serverId'] as num?)?.toInt(),
      senderId: (map['senderId'] as num).toInt(),
      receiverId: (map['receiverId'] as num).toInt(),
      content: map['content'] as String,
      createdAt: DateTime.parse(map['createdAt'] as String),
      status: ChatMessageStatus.values.byName(map['status'] as String),
    );
  }

  ChatMessage copyWith({int? serverId, DateTime? createdAt, ChatMessageStatus? status}) {
    return ChatMessage(
      clientId: clientId,
      serverId: serverId ?? this.serverId,
      senderId: senderId,
      receiverId: receiverId,
      content: content,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
    );
  }
}
