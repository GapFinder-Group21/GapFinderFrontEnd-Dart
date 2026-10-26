import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';

// Table gaps: the free gaps of the user
class GapDao {
  static const table = 'gaps';

  final Future<Database> Function() _database;

  GapDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Deletes the gaps of the user and saves the new ones in one transaction
  Future<void> replaceAllForUser(int userId, List<Gap> gaps) async {
    final db = await _database();
    final savedAt = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      for (final g in gaps) {
        batch.insert(
          table,
          {
            'id': g.id,
            'user_id': userId,
            'start_time': g.startTime.toIso8601String(),
            'end_time': g.endTime.toIso8601String(),
            'saved_at': savedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  // Removes the gaps of the user (logout)
  Future<void> deleteForUser(int userId) async {
    final db = await _database();
    await db.delete(table, where: 'user_id = ?', whereArgs: [userId]);
  }

  Future<List<Gap>> getAllForUser(int userId) async {
    final db = await _database();
    final rows = await db.query(table, where: 'user_id = ?', whereArgs: [userId], orderBy: 'start_time');
    return rows.map(_fromRow).toList();
  }

  Future<Gap?> getById(int id) async {
    final db = await _database();
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  // When the gaps of the user were saved last, or null if there are none
  Future<DateTime?> lastSavedAt(int userId) async {
    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT MAX(saved_at) AS saved_at FROM $table WHERE user_id = ?',
      [userId],
    );
    final value = rows.first['saved_at'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  Gap _fromRow(Map<String, Object?> row) {
    return Gap(
      id: row['id'] as int,
      startTime: DateTime.parse(row['start_time'] as String),
      endTime: DateTime.parse(row['end_time'] as String),
      userId: row['user_id'] as int?,
    );
  }
}
