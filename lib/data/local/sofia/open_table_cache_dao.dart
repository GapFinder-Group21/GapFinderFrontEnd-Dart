import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';

// Which list a saved table belongs to
class OpenTableListType {
  // Tab "open tables" (open_tables_view)
  static const all = 'ALL';
  // "My open tables" (my_open_tables_view)
  static const mine = 'MINE';
}

// Table open_tables_cache: the lists of open tables, each table as JSON.
// The primary key is (id, list_type): a table that is in both lists is saved once in each one,
// and replaceAll only deletes the rows of its own list_type.
class OpenTableCacheDao {
  static const table = 'open_tables_cache';

  final Future<Database> Function() _database;

  OpenTableCacheDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Deletes the list_type rows and saves the new ones in one transaction
  Future<void> replaceAll(String listType, List<OpenTable> tables) async {
    final db = await _database();
    final savedAt = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete(table, where: 'list_type = ?', whereArgs: [listType]);
      for (final t in tables) {
        batch.insert(
          table,
          {
            'id': t.id,
            'json': jsonEncode(t.toCacheJson()),
            'list_type': listType,
            'saved_at': savedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  // Removes every saved list (logout): these rows do not belong to a user
  Future<void> clear() async {
    final db = await _database();
    await db.delete(table);
  }

  // Removes one table from one saved list (for example a table the user left, from 'MINE')
  Future<void> deleteById(String listType, int id) async {
    final db = await _database();
    await db.delete(table, where: 'list_type = ? AND id = ?', whereArgs: [listType, id]);
  }

  Future<List<OpenTable>> getAll(String listType) async {
    final db = await _database();
    final rows = await db.query(table, where: 'list_type = ?', whereArgs: [listType], orderBy: 'id');
    return rows.map(_fromRow).toList();
  }

  Future<OpenTable?> getById(int id, {String? listType}) async {
    final db = await _database();
    final rows = await db.query(
      table,
      where: listType == null ? 'id = ?' : 'id = ? AND list_type = ?',
      whereArgs: listType == null ? [id] : [id, listType],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  // When the list was saved last, or null if it is empty
  Future<DateTime?> lastSavedAt(String listType) async {
    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT MAX(saved_at) AS saved_at FROM $table WHERE list_type = ?',
      [listType],
    );
    final value = rows.first['saved_at'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  OpenTable _fromRow(Map<String, Object?> row) {
    return OpenTable.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>);
  }
}
