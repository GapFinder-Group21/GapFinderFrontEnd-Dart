import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/chat_message_dao.dart';
import 'package:gapfinderfrontend_dart/models/chat_message.dart';

ChatMessage _msg(String clientId, {int? serverId, int sender = 1, ChatMessageStatus status = ChatMessageStatus.sent, int minute = 0}) {
  return ChatMessage(
    clientId: clientId,
    serverId: serverId,
    senderId: sender,
    receiverId: sender == 1 ? 2 : 1,
    content: 'hola $clientId',
    createdAt: DateTime(2026, 11, 16, 10, minute),
    status: status,
  );
}

void main() {
  sqfliteFfiInit();
  late Database db;
  late ChatMessageDao dao;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = ChatMessageDao(database: () async => db);
  });

  tearDown(() => db.close());

  test('saves a chat and reads it back in order: sent by server id, then the pending ones', () async {
    await dao.upsertAll(1, 2, [
      _msg('c', status: ChatMessageStatus.pending, minute: 1),
      _msg('b', serverId: 20, sender: 2),
      _msg('a', serverId: 10),
    ]);

    final chat = await dao.getConversation(1, 2);
    expect(chat.map((m) => m.clientId), ['a', 'b', 'c']);
    expect(chat[1].receiverId, 1); // the friend sent it to the user
    expect(chat[2].status, ChatMessageStatus.pending);
  });

  test('the same clientId stays one row when the back confirms it', () async {
    await dao.upsert(1, 2, _msg('x', status: ChatMessageStatus.pending));
    await dao.upsert(1, 2, _msg('x', serverId: 5));

    final chat = await dao.getConversation(1, 2);
    expect(chat, hasLength(1));
    expect(chat.single.serverId, 5);
    expect(chat.single.status, ChatMessageStatus.sent);
  });

  test('chats of other friends or users are not mixed, and logout removes only that user', () async {
    await dao.upsert(1, 2, _msg('a'));
    await dao.upsert(1, 3, _msg('b'));
    await dao.upsert(9, 2, _msg('c', sender: 9));

    expect(await dao.getConversation(1, 2), hasLength(1));

    await dao.deleteForUser(1);
    expect(await dao.getConversation(1, 2), isEmpty);
    expect(await dao.getConversation(1, 3), isEmpty);
    expect(await dao.getConversation(9, 2), hasLength(1));
  });

  test('updateStatus marks a message as failed', () async {
    await dao.upsert(1, 2, _msg('a', status: ChatMessageStatus.pending));
    await dao.updateStatus('a', ChatMessageStatus.failed);
    expect((await dao.getConversation(1, 2)).single.status, ChatMessageStatus.failed);
  });
}
