import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/cache_json.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';

// Match candidates that the user saw, one per match (table seen_candidates).
// The JSON keeps both gaps with their users, so the candidate can be shown again as it was.
class SeenCandidatesDao {
  final Future<Database> Function() _database;

  SeenCandidatesDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Saves (or replaces) the candidate of a match
  Future<void> save(int matchId, MatchCandidate candidate) async {
    final db = await _database();
    await db.insert(
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
