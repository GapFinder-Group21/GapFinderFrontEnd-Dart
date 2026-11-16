import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/match_rating_outbox.dart';

// History of the user's matches and their ratings
class MatchRatingService {
  // Every match of the user with both ratings - GET /matches/user/{userId}/history
  // Returns the raw JSON text: it is parsed in an isolate (processMatchHistory), not here
  Future<String> getHistory(int userId) async {
    final res = await ApiClient.get('/matches/user/$userId/history');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'No pudimos cargar tus matches'));
    }
    return utf8.decode(res.bodyBytes);
  }

  // Rates a completed match - POST /matches/{matchId}/ratings {stars, comment}
  // The rater is the authenticated user. 409 means it was already rated: it counts as done.
  Future<void> rate(int matchId, int stars, String? comment) async {
    final res = await ApiClient.post(
      MatchRatingOutbox.endpoint(matchId),
      body: MatchRatingOutbox.body(stars, comment),
    );

    if (res.statusCode == 201 || res.statusCode == 200 || res.statusCode == 409) return;
    throw Exception(_errorMessage(res, 'No se pudo enviar tu calificación'));
  }

  // The back sends errors as plain text or as JSON {"error": "..."}
  String _errorMessage(dynamic res, String fallback) {
    final body = utf8.decode(res.bodyBytes).trim();
    if (body.isEmpty) return fallback;

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && (decoded['error'] ?? decoded['message']) != null) {
        return plainBackendText((decoded['error'] ?? decoded['message']).toString(), fallback);
      }
    } catch (_) {
      // Not JSON, it is plain text
    }
    return plainBackendText(body, fallback);
  }
}
