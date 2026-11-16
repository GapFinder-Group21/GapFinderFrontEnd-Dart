import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/chat_message_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/outbox_keys.dart';
import 'package:gapfinderfrontend_dart/models/chat_message.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/chat_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/chat_processing.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/chat_view_model.dart';

class _FakeConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool online;
  _FakeConnectivity(this.online);

  void setOnline(bool value) {
    online = value;
    _controller.add(value);
  }

  @override
  bool get isOnline => online;
  @override
  Stream<bool> get onStatusChange => _controller.stream;
  @override
  Future<bool> checkNow() async => online;
  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
}

// Fake back: answers what each test sets
class _FakeChat extends ChatService {
  final List<int> afterIds = [];
  String body = '[]';
  // null = it works; otherwise this error is thrown when sending
  Object? sendError;
  int sent = 0;

  @override
  Future<String> getConversationBody(int userId, int friendId, {int afterId = 0}) async {
    afterIds.add(afterId);
    return body;
  }

  @override
  Future<ChatMessage?> send(int receiverId, String content, String clientId) async {
    sent++;
    final error = sendError;
    if (error != null) throw error;
    return ChatMessage(
      clientId: clientId,
      serverId: 100 + sent,
      senderId: 1,
      receiverId: receiverId,
      content: content,
      createdAt: DateTime(2026, 11, 16, 10),
    );
  }
}

final _friend = User(id: 2, name: 'Ana', email: 'ana@gmail.com', career: 'Systems');

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 50));

void main() {
  sqfliteFfiInit();
  late Database db;
  late OutboxService outbox;
  late ChatMessageDao dao;
  late _FakeChat chat;
  late _FakeConnectivity connectivity;
  late List<int> outboxCodes; // answers of the back to the outbox, one per request
  late ChatViewModel vm;

  ChatViewModel build({ChatMessageDao? withDao}) => ChatViewModel(
        _friend,
        chatService: chat,
        dao: withDao ?? dao,
        connectivity: connectivity,
        outbox: outbox,
        readUserId: () async => 1,
        // Same function the isolate runs, called directly in the test
        merge: (payload) async => mergeChatMessages(payload),
        pollEvery: const Duration(hours: 1),
      );

  setUp(() async {
    ChatViewModel.clearChatCache();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = ChatMessageDao(database: () async => db);
    outboxCodes = [];
    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async {
        final code = outboxCodes.isEmpty ? 201 : outboxCodes.removeAt(0);
        final text = code == 422 ? '{"error":"Solo puedes enviar mensajes a tus amigos"}' : '{}';
        return http.Response.bytes(utf8.encode(text), code);
      },
    );
    chat = _FakeChat();
    connectivity = _FakeConnectivity(true);
  });

  tearDown(() async {
    vm.dispose();
    await outbox.dispose();
    await db.close();
  });

  test('offline: the message shows as pending and goes to the outbox with its key', () async {
    connectivity.online = false;
    vm = build();
    await vm.init();

    expect(vm.send('hola'), isNull);
    await _settle();

    final message = vm.messages.single;
    expect(message.status, ChatMessageStatus.pending);
    expect(chat.sent, 0);
    expect(await outbox.isPending(OutboxKeys.chatMessage(1, message.clientId)), isTrue);
    expect((await dao.getConversation(1, 2)).single.status, ChatMessageStatus.pending);
  });

  test('it turns sent when the outbox sends it', () async {
    connectivity.online = false;
    vm = build();
    await vm.init();
    vm.send('hola');
    await _settle();

    await outbox.flush();
    await _settle();

    expect(vm.messages.single.status, ChatMessageStatus.sent);
  });

  test('a refusal of the back marks it failed with the reason, and retry tries again', () async {
    connectivity.online = false;
    vm = build();
    await vm.init();
    vm.send('hola');
    await _settle();

    outboxCodes = [422];
    await outbox.flush();
    await _settle();

    final message = vm.messages.single;
    expect(message.status, ChatMessageStatus.failed);
    expect(vm.failReason(message.clientId), 'Solo puedes enviar mensajes a tus amigos');

    vm.retry(message.clientId);
    await _settle();
    expect(vm.messages.single.status, ChatMessageStatus.pending);
    expect(vm.messages.single.clientId, message.clientId); // same id: the back never stores it twice
  });

  test('online: the Future handler marks it sent with the server id', () async {
    vm = build();
    await vm.init();

    vm.send('hola');
    await _settle();

    expect(chat.sent, 1);
    expect(vm.messages.single.status, ChatMessageStatus.sent);
    expect(vm.messages.single.serverId, 101);
  });

  test('online: the error handler marks it failed when the back refuses it', () async {
    chat.sendError = ChatRefusedException('El mensaje no puede estar vacío');
    vm = build();
    await vm.init();

    vm.send('hola');
    await _settle();

    final message = vm.messages.single;
    expect(message.status, ChatMessageStatus.failed);
    expect(vm.failReason(message.clientId), 'El mensaje no puede estar vacío');
  });

  test('online: if the network fails while sending it goes to the outbox', () async {
    chat.sendError = const SocketException('no network');
    vm = build();
    await vm.init();

    vm.send('hola');
    await _settle();

    final message = vm.messages.single;
    expect(message.status, ChatMessageStatus.pending);
    expect(await outbox.isPending(OutboxKeys.chatMessage(1, message.clientId)), isTrue);
  });

  test('the polling asks only for the messages after the last server id', () async {
    chat.body = jsonEncode([
      {'id': 5, 'clientId': 'a', 'senderId': 2, 'receiverId': 1, 'content': 'hola', 'createdAt': '2026-11-16T10:00:00'},
    ]);
    vm = build();
    await vm.init();
    expect(chat.afterIds, [0]);
    expect(vm.messages.single.serverId, 5);

    chat.body = '[]';
    await vm.fetchNew();
    expect(chat.afterIds, [0, 5]);
  });

  test('offline the polling stops, and it starts again when the network is back', () async {
    vm = build();
    await vm.init();
    expect(vm.isPolling, isTrue);

    connectivity.setOnline(false);
    await _settle();
    expect(vm.isPolling, isFalse);
    expect(vm.isOffline, isTrue);

    connectivity.setOnline(true);
    await _settle();
    expect(vm.isPolling, isTrue);
  });

  test('opening the chat again uses the LRU cache, without reading SQLite', () async {
    chat.body = jsonEncode([
      {'id': 5, 'clientId': 'a', 'senderId': 2, 'receiverId': 1, 'content': 'hola', 'createdAt': '2026-11-16T10:00:00'},
    ]);
    vm = build();
    await vm.init();
    vm.dispose();

    // A DAO on an empty database: if the chat shows, it came from memory
    final emptyDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(emptyDb);
    connectivity.online = false;
    vm = build(withDao: ChatMessageDao(database: () async => emptyDb));
    await vm.init();

    expect(vm.messages.single.clientId, 'a');
    await emptyDb.close();
  });

  test('empty or too long messages are not sent', () async {
    vm = build();
    await vm.init();

    expect(vm.send('   '), isNotNull);
    expect(vm.send('x' * 501), isNotNull);
    expect(vm.messages, isEmpty);
  });
}
