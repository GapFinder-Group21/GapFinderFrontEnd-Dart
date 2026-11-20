import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';

// STORAGE MIGUEL: SQLite (study_periods table)
// Saves the study periods of each user so the study mode works without internet: a period turned on
// offline is here with synced = 0 until the outbox sends it.
class StudyPeriodDao {
  static const table = 'study_periods';

  final Future<Database> Function() _database;

  StudyPeriodDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Saves or replaces one period (the key is the client id)
  Future<void> upsert(StudyPeriod period) async {
    final db = await _database();
    await db.insert(table, _row(period), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // Replaces every period of the user with the given ones, in one transaction (one batch)
  Future<void> replaceAllForUser(int userId, List<StudyPeriod> periods) async {
    final db = await _database();
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete(table, where: 'user_id = ?', whereArgs: [userId]);
      for (final period in periods) {
        batch.insert(table, _row(period), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  // Every period of the user, the earliest first (the ones that already ended included)
  Future<List<StudyPeriod>> getForUser(int userId) async {
    final db = await _database();
    final rows = await db.query(table, where: 'user_id = ?', whereArgs: [userId], orderBy: 'start_time ASC');
    return rows.map(_fromRow).toList();
  }

  // One period by its client id (null if it is not saved)
  Future<StudyPeriod?> find(String clientId) async {
    final db = await _database();
    final rows = await db.query(table, where: 'client_id = ?', whereArgs: [clientId], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  // The back has the period now: it is marked as synced and keeps the id the back gave it
  Future<void> markSynced(String clientId, int? serverId) async {
    final db = await _database();
    await db.update(
      table,
      {'synced': 1, 'server_id': serverId},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  Future<void> delete(String clientId) async {
    final db = await _database();
    await db.delete(table, where: 'client_id = ?', whereArgs: [clientId]);
  }

  // Removes the periods of the user that already ended; returns how many
  Future<int> deleteEnded(int userId, DateTime now) async {
    final db = await _database();
    return db.delete(
      table,
      where: 'user_id = ? AND end_time <= ?',
      whereArgs: [userId, now.toIso8601String()],
    );
  }

  // Removes every period of the user (logout)
  Future<void> deleteForUser(int userId) async {
    final db = await _database();
    await db.delete(table, where: 'user_id = ?', whereArgs: [userId]);
  }

  // Removes every period of every user (logout when the session expired and the user is not known)
  Future<void> deleteAll() async {
    final db = await _database();
    await db.delete(table);
  }

  Map<String, Object?> _row(StudyPeriod p) => {
        'client_id': p.clientId,
        'server_id': p.serverId,
        'user_id': p.userId,
        'gap_id': p.gapId,
        'start_time': p.startTime.toIso8601String(),
        'end_time': p.endTime.toIso8601String(),
        'synced': p.synced ? 1 : 0,
      };

  StudyPeriod _fromRow(Map<String, Object?> row) {
    return StudyPeriod(
      clientId: row['client_id'] as String,
      serverId: row['server_id'] as int?,
      userId: row['user_id'] as int,
      gapId: row['gap_id'] as int?,
      startTime: DateTime.parse(row['start_time'] as String),
      endTime: DateTime.parse(row['end_time'] as String),
      synced: row['synced'] == 1,
    );
  }
}
