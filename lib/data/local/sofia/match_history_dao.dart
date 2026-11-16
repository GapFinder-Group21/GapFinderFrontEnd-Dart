import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/json_row_dao.dart';
import 'package:gapfinderfrontend_dart/models/match_history_item.dart';

// Estrategia: Local storage (SQLite). Table match_history(id, user_id, json, saved_at) of gapfinder.db:
// the last history the back answered for each user, so "Mis matches" opens without internet and says
// "actualizado a las HH:mm". The whole item is kept as JSON (it has the other user and both ratings).
class MatchHistoryDao extends JsonRowDao<MatchHistoryItem> {
  static const tableName = 'match_history';

  final Future<Database> Function() _db;

  MatchHistoryDao({Future<Database> Function()? database})
      : _db = database ?? (() => AppDatabase.instance.database),
        super(tableName, database: database);

  @override
  int idOf(MatchHistoryItem item) => item.matchId;

  @override
  Map<String, dynamic> toJson(MatchHistoryItem item) => item.toJson();

  @override
  MatchHistoryItem fromJson(Map<String, dynamic> json) => MatchHistoryItem.fromJson(json);

  // Removes the history of the user (logout)
  Future<void> deleteForUser(int userId) async {
    final db = await _db();
    await db.delete(tableName, where: 'user_id = ?', whereArgs: [userId]);
  }
}
