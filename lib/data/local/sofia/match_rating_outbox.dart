// Eventual connectivity for the match ratings: the type, key, endpoint and body of a rating
// that waits in the SQLite outbox until the internet comes back.
class MatchRatingOutbox {
  static const type = 'match_rating';

  // The user id is part of the key: a rating of one user is never sent with the token of the next one.
  // One key per match: many taps on "Enviar" leave a single queued rating.
  static String key(int userId, int matchId) => 'match_rating:$userId:$matchId';

  // Prefix of every rating key of a user
  static String prefix(int userId) => 'match_rating:$userId:';

  // The match id of a key of this user, or null if the key is not one of theirs
  static int? matchIdOf(String key, int userId) {
    final p = prefix(userId);
    if (!key.startsWith(p)) return null;
    return int.tryParse(key.substring(p.length));
  }

  static String endpoint(int matchId) => '/matches/$matchId/ratings';

  // An empty comment is not sent
  static Map<String, dynamic> body(int stars, String? comment) {
    final text = comment?.trim();
    return {'stars': stars, 'comment': (text == null || text.isEmpty) ? null : text};
  }
}
