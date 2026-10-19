import 'package:gapfinderfrontend_dart/data/local/joel/cache_json.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/json_row_dao.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';

// Matches of the user (table matches). gap_id is the user's own gap in that match.
class MatchDao extends JsonRowDao<Match> {
  MatchDao({super.database}) : super('matches');

  @override
  int idOf(Match item) => item.id;

  @override
  Map<String, dynamic> toJson(Match item) => matchCacheJson(item);

  @override
  Match fromJson(Map<String, dynamic> json) => Match.fromJson(json);

  // Replaces the user's matches; userGapIds tells which side of each match is the user's
  Future<void> replaceAllForUserGaps(int userId, List<Match> matches, Set<int> userGapIds) {
    final savedAt = DateTime.now().toIso8601String();
    final rows = matches
        .map((m) => {
              ...rowOf(m, userId, savedAt),
              'gap_id': userGapIds.contains(m.proposerGapId) ? m.proposerGapId : m.acceptorGapId,
            })
        .toList();
    return replaceRowsForUser(userId, rows);
  }

  // Saves one match (for example an invitation) without touching the others
  Future<void> upsertForUser(int userId, Match match, int? gapId) {
    return upsertRow({
      ...rowOf(match, userId, DateTime.now().toIso8601String()),
      'gap_id': gapId,
    });
  }
}
