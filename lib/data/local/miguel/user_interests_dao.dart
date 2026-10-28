import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';

// An interest chosen by a user; synced is true when the back already received it
class UserInterestRow {
  final int userId;
  final int interestId;
  final bool synced;

  const UserInterestRow({required this.userId, required this.interestId, required this.synced});
}

// Interests chosen by each user (table user_interests, key = user + interest)
class UserInterestsDao {
  final Future<Database> Function() _database;

  UserInterestsDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Replaces the interests of the user with the chosen ones, in one batch.
  // syncedIds: the interests the back already received (synced = 1); the others stay with synced = 0
  Future<void> replaceAllForUser(int userId, Set<int> interestIds, Set<int> syncedIds) async {
    final db = await _database();

    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete('user_interests', where: 'user_id = ?', whereArgs: [userId]);
      for (final interestId in interestIds) {
        batch.insert(
          'user_interests',
          {'user_id': userId, 'interest_id': interestId, 'synced': syncedIds.contains(interestId) ? 1 : 0},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<UserInterestRow>> getAllForUser(int userId) async {
    final db = await _database();
    final rows = await db.query('user_interests', where: 'user_id = ?', whereArgs: [userId], orderBy: 'interest_id ASC');
    return rows
        .map((r) => UserInterestRow(
              userId: r['user_id'] as int,
              interestId: r['interest_id'] as int,
              synced: r['synced'] == 1,
            ))
        .toList();
  }
}
