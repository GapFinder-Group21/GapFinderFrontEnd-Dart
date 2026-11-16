import 'dart:convert';

// MULTITHREADING JOEL: Isolate (merge the chat messages)
// Estrategia: Isolate. Runs with compute(...) in another isolate, so parsing the answer of the back,
// joining it with the local messages, removing duplicates and sorting never blocks the screen.
// It is top-level and gets only simple data (a map with a list of maps and a JSON text), because
// an isolate does not share memory with the app.
//
// payload: {'local': [message maps], 'remote': '<JSON text of the back>'}
// Returns the whole chat as message maps (see ChatMessage.toMap), in order.
List<Map<String, dynamic>> mergeChatMessages(Map<String, dynamic> payload) {
  final byClientId = <String, Map<String, dynamic>>{};

  for (final m in (payload['local'] as List)) {
    final map = Map<String, dynamic>.from(m as Map);
    byClientId[map['clientId'] as String] = map;
  }

  final remoteText = (payload['remote'] as String?)?.trim() ?? '';
  if (remoteText.isNotEmpty) {
    for (final r in (jsonDecode(remoteText) as List)) {
      final json = Map<String, dynamic>.from(r as Map);
      final clientId = json['clientId'] as String;
      // What the back says wins: a local pending or failed message with the same clientId is now sent
      byClientId[clientId] = {
        'clientId': clientId,
        'serverId': (json['id'] as num?)?.toInt(),
        'senderId': (json['senderId'] as num).toInt(),
        'receiverId': (json['receiverId'] as num).toInt(),
        'content': json['content'] as String? ?? '',
        'createdAt': DateTime.parse(json['createdAt'] as String).toIso8601String(),
        'status': 'sent',
      };
    }
  }

  final merged = byClientId.values.toList()..sort(_compare);
  return merged;
}

// Messages the back has go first, in the order the back stored them (server id).
// The ones not sent yet go last, by the time they were written.
int _compare(Map<String, dynamic> a, Map<String, dynamic> b) {
  final aId = a['serverId'] as int?;
  final bId = b['serverId'] as int?;
  if (aId != null && bId != null) return aId.compareTo(bId);
  if (aId != null) return -1;
  if (bId != null) return 1;
  return (a['createdAt'] as String).compareTo(b['createdAt'] as String);
}
