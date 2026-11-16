import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/chat_processing.dart';

Map<String, dynamic> _local(String clientId, {int? serverId, String status = 'sent', int minute = 0}) => {
      'clientId': clientId,
      'serverId': serverId,
      'senderId': 1,
      'receiverId': 2,
      'content': clientId,
      'createdAt': DateTime(2026, 11, 16, 10, minute).toIso8601String(),
      'status': status,
    };

Map<String, dynamic> _remote(String clientId, int id, {int sender = 2}) => {
      'id': id,
      'clientId': clientId,
      'senderId': sender,
      'receiverId': sender == 1 ? 2 : 1,
      'content': clientId,
      'createdAt': '2026-11-16T10:0$id:00',
    };

void main() {
  test('a pending local message confirmed by the back is kept once, as sent', () {
    final merged = mergeChatMessages({
      'local': [_local('mine', status: 'pending')],
      'remote': jsonEncode([_remote('mine', 7, sender: 1)]),
    });

    expect(merged, hasLength(1));
    expect(merged.single['status'], 'sent');
    expect(merged.single['serverId'], 7);
  });

  test('messages of the back go in server id order and the ones not sent go last', () {
    final merged = mergeChatMessages({
      'local': [
        _local('later', status: 'pending', minute: 9),
        _local('old', serverId: 1),
      ],
      'remote': jsonEncode([_remote('c', 3), _remote('b', 2)]),
    });

    expect(merged.map((m) => m['clientId']), ['old', 'b', 'c', 'later']);
  });

  test('an empty answer keeps the local chat', () {
    final merged = mergeChatMessages({
      'local': [_local('a', serverId: 1)],
      'remote': '[]',
    });
    expect(merged.single['clientId'], 'a');
  });
}
