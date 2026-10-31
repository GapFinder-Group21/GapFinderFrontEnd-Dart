import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/cache_json.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';

// Match candidates that the user saw, one per match (table seen_candidates).
// The JSON keeps both gaps with their users, so the candidate can be shown again as it was.
// Only the last maxRows are kept.
class SeenCandidatesDao {
  // The table does not grow forever: older rows are deleted when a new one is saved
  static const maxRows = 20;

  // A request that waits in the outbox has no match id yet. It is saved with a negative key made from its two
  // gaps (a real match id is always positive) and replaced by the real id when the request is confirmed.
  static int queuedKey(int proposerGapId, int acceptorGapId) => -(proposerGapId * 1000000 + acceptorGapId);

  final Future<Database> Function() _database;

  SeenCandidatesDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Saves (or replaces) the candidate of a match and keeps only the last maxRows
  Future<void> save(int matchId, MatchCandidate candidate) async {
    final db = await _database();
    await db.transaction((txn) async {
      await txn.insert(
        'seen_candidates',
        {
          'match_id': matchId,
          'json': jsonEncode({
            'proposerGap': gapCacheJson(candidate.proposerGap),
            'acceptorGap': gapCacheJson(candidate.acceptorGap),
            'score': candidate.score,
          }),
          'saved_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.rawDelete(
        'DELETE FROM seen_candidates WHERE match_id NOT IN '
        '(SELECT match_id FROM seen_candidates ORDER BY saved_at DESC, match_id DESC LIMIT ?)',
        [maxRows],
      );
    });
  }

  // The candidate of a request that is still in the outbox (no match id yet)
  Future<void> saveQueued(int proposerGapId, int acceptorGapId, MatchCandidate candidate) {
    return save(queuedKey(proposerGapId, acceptorGapId), candidate);
  }

  // Removes the candidate of a queued request (it was confirmed with its real id, or it was cancelled)
  Future<void> deleteQueued(int proposerGapId, int acceptorGapId) async {
    final db = await _database();
    await db.delete('seen_candidates', where: 'match_id = ?', whereArgs: [queuedKey(proposerGapId, acceptorGapId)]);
  }

  Future<MatchCandidate?> getById(int matchId) async {
    final db = await _database();
    final rows = await db.query('seen_candidates', where: 'match_id = ?', whereArgs: [matchId], limit: 1);
    return rows.isEmpty ? null : _decode(rows.first);
  }

  // All the candidates, the last one seen first
  Future<List<MatchCandidate>> getAll() async {
    final db = await _database();
    final rows = await db.query('seen_candidates', orderBy: 'saved_at DESC');
    return rows.map(_decode).toList();
  }

  MatchCandidate _decode(Map<String, Object?> row) =>
      MatchCandidate.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>);
}
