import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';

// Shared logic of the DAOs whose rows are (id, user_id, json, saved_at, ...extra columns)
abstract class JsonRowDao<T> {
  final String table;
  final Future<Database> Function() _database;

  JsonRowDao(this.table, {Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  int idOf(T item);
  Map<String, dynamic> toJson(T item);
  T fromJson(Map<String, dynamic> json);

  // Extra columns of the table (for example is_read)
  Map<String, Object?> extraColumns(T item) => const {};

  Map<String, Object?> rowOf(T item, int userId, String savedAt) => {
        'id': idOf(item),
        'user_id': userId,
        'json': jsonEncode(toJson(item)),
        'saved_at': savedAt,
        ...extraColumns(item),
      };

  // Replaces the rows of the user with the last network answer, in one batch
  Future<void> replaceAllForUser(int userId, List<T> items) {
    final savedAt = DateTime.now().toIso8601String();
    return replaceRowsForUser(userId, items.map((i) => rowOf(i, userId, savedAt)).toList());
  }

  Future<void> replaceRowsForUser(int userId, List<Map<String, Object?>> rows) async {
    final db = await _database();
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      for (final row in rows) {
        batch.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  // Saves or replaces one row
  Future<void> upsertRow(Map<String, Object?> row) async {
    final db = await _database();
    await db.insert(table, row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<T>> getAllForUser(int userId) async {
    final db = await _database();
    final rows = await db.query(table, where: 'user_id = ?', whereArgs: [userId], orderBy: 'id ASC');
    return rows.map(_decode).toList();
  }

  Future<T?> getById(int id) async {
    final db = await _database();
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _decode(rows.first);
  }

  // When the rows of the user were last saved, or null if there are none
  Future<DateTime?> lastSavedAt(int userId) async {
    final db = await _database();
    final rows = await db.rawQuery('SELECT MAX(saved_at) AS last FROM $table WHERE user_id = ?', [userId]);
    final last = rows.first['last'] as String?;
    return last == null ? null : DateTime.parse(last);
  }

  T _decode(Map<String, Object?> row) =>
      fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>);
}
