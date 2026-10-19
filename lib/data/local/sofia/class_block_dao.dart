import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/utils/time_formatter_util.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/models/enums/day_of_week_enum.dart';

// Table class_blocks: the classes of the user
class ClassBlockDao {
  static const table = 'class_blocks';

  final Future<Database> Function() _database;

  ClassBlockDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Deletes the classes of the user and saves the new ones in one transaction
  Future<void> replaceAllForUser(int userId, List<ClassBlock> blocks) async {
    final db = await _database();
    final savedAt = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      for (final b in blocks) {
        batch.insert(
          table,
          {
            'id': b.id,
            'user_id': userId,
            'subject': b.subject,
            'location': b.location,
            'day_of_week': b.dayOfWeek.toJson(),
            'start_time': TimeFormatterUtil.formatTime(b.startTime),
            'end_time': TimeFormatterUtil.formatTime(b.endTime),
            'saved_at': savedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<ClassBlock>> getAllForUser(int userId) async {
    final db = await _database();
    final rows = await db.query(table, where: 'user_id = ?', whereArgs: [userId], orderBy: 'id');
    return rows.map(_fromRow).toList();
  }

  Future<ClassBlock?> getById(int id) async {
    final db = await _database();
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  // When the classes of the user were saved last, or null if there are none
  Future<DateTime?> lastSavedAt(int userId) async {
    final db = await _database();
    final rows = await db.rawQuery(
      'SELECT MAX(saved_at) AS saved_at FROM $table WHERE user_id = ?',
      [userId],
    );
    final value = rows.first['saved_at'] as String?;
    return value == null ? null : DateTime.tryParse(value);
  }

  ClassBlock _fromRow(Map<String, Object?> row) {
    return ClassBlock(
      id: row['id'] as int,
      subject: (row['subject'] as String?) ?? '',
      location: (row['location'] as String?) ?? '',
      dayOfWeek: DayOfWeekEnum.fromString(row['day_of_week'] as String),
      startTime: TimeFormatterUtil.parseTime(row['start_time'] as String),
      endTime: TimeFormatterUtil.parseTime(row['end_time'] as String),
    );
  }
}
