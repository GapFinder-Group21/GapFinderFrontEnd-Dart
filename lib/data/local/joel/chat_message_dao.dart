import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/models/chat_message.dart';

// STORAGE JOEL: SQLite (chat_messages table)
// Saves the messages of each chat (user + friend) so they can be read without internet
class ChatMessageDao {
  static const table = 'chat_messages';

  final Future<Database> Function() _database;

  ChatMessageDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Saves or replaces many messages in one transaction (one batch)
  Future<void> upsertAll(int userId, int friendId, List<ChatMessage> messages) async {
    if (messages.isEmpty) return;
    final db = await _database();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final m in messages) {
        batch.insert(table, _row(userId, friendId, m), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<void> upsert(int userId, int friendId, ChatMessage message) => upsertAll(userId, friendId, [message]);

  // The chat in order: the ones the back has (by server id) and then the ones not sent yet
  Future<List<ChatMessage>> getConversation(int userId, int friendId) async {
    final db = await _database();
    final rows = await db.query(
      table,
      where: 'user_id = ? AND friend_id = ?',
      whereArgs: [userId, friendId],
      orderBy: 'server_id IS NULL, server_id ASC, created_at ASC',
    );
    return rows.map((r) => _fromRow(r, userId, friendId)).toList();
  }

  Future<void> updateStatus(String clientId, ChatMessageStatus status) async {
    final db = await _database();
    await db.update(table, {'status': status.name}, where: 'client_id = ?', whereArgs: [clientId]);
  }

  // Removes every chat of the user (logout)
  Future<void> deleteForUser(int userId) async {
    final db = await _database();
    await db.delete(table, where: 'user_id = ?', whereArgs: [userId]);
  }

  Map<String, Object?> _row(int userId, int friendId, ChatMessage m) => {
        'client_id': m.clientId,
        'server_id': m.serverId,
        'user_id': userId,
        'friend_id': friendId,
        'sender_id': m.senderId,
        'content': m.content,
        'created_at': m.createdAt.toIso8601String(),
        'status': m.status.name,
      };

  ChatMessage _fromRow(Map<String, Object?> row, int userId, int friendId) {
    final senderId = row['sender_id'] as int;
    return ChatMessage(
      clientId: row['client_id'] as String,
      serverId: row['server_id'] as int?,
      senderId: senderId,
      // The receiver is the other person of the chat
      receiverId: senderId == userId ? friendId : userId,
      content: row['content'] as String,
      createdAt: DateTime.parse(row['created_at'] as String),
      status: ChatMessageStatus.values.byName(row['status'] as String),
    );
  }
}
