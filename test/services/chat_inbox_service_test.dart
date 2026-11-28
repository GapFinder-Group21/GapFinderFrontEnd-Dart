import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/models/chat_message.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/chat_inbox_service.dart';
import 'package:gapfinderfrontend_dart/services/chat_service.dart';

class _Online implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  Stream<bool> get onStatusChange => const Stream.empty();
  @override
  Future<bool> checkNow() async => true;
  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
}

// Fake back: the messages of each friend; it answers only the ones newer than afterId (like the real one)
class _FakeChat extends ChatService {
  final Map<int, List<Map<String, dynamic>>> byFriend = {};

  void add(int friendId, int id, int senderId, String content, DateTime at) {
    byFriend.putIfAbsent(friendId, () => []).add({
      'id': id,
      'clientId': 'c$id',
      'senderId': senderId,
      'receiverId': senderId == 1 ? friendId : 1,
      'content': content,
      'createdAt': at.toIso8601String(),
    });
  }

  @override
  Future<String> getConversationBody(int userId, int friendId, {int afterId = 0}) async {
    final list = (byFriend[friendId] ?? []).where((m) => (m['id'] as int) > afterId).take(50).toList();
    return jsonEncode(list);
  }
}

final _ana = User(id: 2, name: 'Ana', email: 'ana@x.com', career: 'ISIS');
final _luis = User(id: 3, name: 'Luis', email: 'luis@x.com', career: 'ISIS');
final _t0 = DateTime(2026, 11, 27, 10);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeChat chat;
  late List<String> shown;
  late ChatInboxService inbox;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    chat = _FakeChat();
    shown = [];
    inbox = ChatInboxService(
      chat: chat,
      connectivity: _Online(),
      readUserId: () async => 1,
      loadFriends: (_) async => [_ana, _luis],
      notifier: (friendId, title, body) async => shown.add('$friendId|$title|$body'),
    );
    // start() also starts a 10 s timer: the tests call pollOnce themselves
    await inbox.start(); // it also starts a round by itself (the first one: old messages are only the starting point)
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });

  tearDown(() => inbox.dispose());

  test('old messages are not notified and do not count as unread', () async {
    chat.add(2, 1, 2, 'hola de antes', _t0);
    inbox.dispose();
    inbox = ChatInboxService(
      chat: chat,
      connectivity: _Online(),
      readUserId: () async => 9, // another user: no saved counters
      loadFriends: (_) async => [_ana, _luis],
      notifier: (friendId, title, body) async => shown.add('$friendId|$title|$body'),
    );
    await inbox.start();
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(shown, isEmpty);
    expect(inbox.unreadFor(2), 0);
    expect(inbox.lastMessageAt(2), _t0);
  });

  test('a new message from a friend is counted and notified', () async {
    chat.add(2, 1, 2, 'hola', _t0.add(const Duration(minutes: 1)));
    await inbox.pollOnce();

    expect(inbox.unreadFor(2), 1);
    expect(inbox.totalUnread, 1);
    expect(shown, ['2|Ana|hola']);
  });

  test('several messages give one notification with the number', () async {
    chat.add(2, 1, 2, 'uno', _t0);
    chat.add(2, 2, 2, 'dos', _t0.add(const Duration(minutes: 1)));
    await inbox.pollOnce();

    expect(inbox.unreadFor(2), 2);
    expect(shown, ['2|Ana|2 mensajes nuevos']);
  });

  test('the same message is not counted twice', () async {
    chat.add(2, 1, 2, 'hola', _t0);
    await inbox.pollOnce();
    await inbox.pollOnce();

    expect(inbox.unreadFor(2), 1);
    expect(shown.length, 1);
  });

  test('my own messages move the chat up but are not unread', () async {
    chat.add(3, 1, 1, 'yo escribí', _t0);
    await inbox.pollOnce();

    expect(inbox.unreadFor(3), 0);
    expect(inbox.lastMessageAt(3), _t0);
    expect(shown, isEmpty);
  });

  test('with the chat open nothing is unread and no notification is shown', () async {
    inbox.openChat(2);
    chat.add(2, 1, 2, 'hola', _t0);
    await inbox.pollOnce();

    expect(inbox.unreadFor(2), 0);
    expect(shown, isEmpty);
  });

  test('opening the chat clears the unread number', () async {
    chat.add(2, 1, 2, 'hola', _t0);
    await inbox.pollOnce();
    expect(inbox.unreadFor(2), 1);

    inbox.openChat(2);
    expect(inbox.unreadFor(2), 0);
  });

  test('messages the chat screen already showed do not count', () async {
    chat.add(2, 1, 2, 'hola', _t0);
    inbox.chatSeen(2, [
      ChatMessage(clientId: 'c1', serverId: 1, senderId: 2, receiverId: 1, content: 'hola', createdAt: _t0),
    ]);
    await inbox.pollOnce();

    expect(inbox.unreadFor(2), 0);
    expect(shown, isEmpty);
  });

  test('friends with the most recent message go first, friends without messages go last', () async {
    final friends = [_ana, _luis, User(id: 4, name: 'Sin chat', email: 's@x.com', career: 'ISIS')];
    chat.add(2, 1, 2, 'viejo', _t0);
    chat.add(3, 2, 3, 'nuevo', _t0.add(const Duration(hours: 1)));
    await inbox.pollOnce();

    final sorted = inbox.sortByRecent(friends, (u) => u.id);
    expect(sorted.map((u) => u.id), [3, 2, 4]);
  });

  test('touch (the user wrote) puts that friend first', () async {
    chat.add(2, 1, 2, 'viejo', _t0);
    await inbox.pollOnce();
    inbox.touch(3, _t0.add(const Duration(minutes: 5)), 'hey');

    expect(inbox.sortByRecent([_ana, _luis], (u) => u.id).first.id, 3);
  });

  test('reset forgets the counters (logout)', () async {
    chat.add(2, 1, 2, 'hola', _t0);
    await inbox.pollOnce();
    await inbox.reset();

    expect(inbox.totalUnread, 0);
    expect(inbox.isStarted, false);
  });
}
