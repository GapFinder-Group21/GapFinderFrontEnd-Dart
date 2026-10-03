import 'dart:convert';
import '../core/api_client.dart';
import '../models/match.dart';
import '../models/match_candidate.dart';

class MatchService {
  // Candidates for a gap - GET /matches/gap/{gapId}/candidates
  Future<List<MatchCandidate>> getCandidates(
      int gapId, {
        bool useSameCareer = false,
        bool useSharedInterests = false,
        bool useEffort = false,
      }) async {
    final res = await ApiClient.get(
      '/matches/gap/$gapId/candidates'
          '?useSameCareer=$useSameCareer'
          '&useSharedInterests=$useSharedInterests'
          '&useEffort=$useEffort',
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting candidates'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => MatchCandidate.fromJson(json)).toList();
  }

  // Send a match request - POST /matches/request
  // El score debe ser el que devolvió getCandidates
  Future<Match> sendRequest(int proposerGapId, int acceptorGapId, double score) async {
    final res = await ApiClient.post(
      '/matches/request'
          '?proposerGapId=$proposerGapId'
          '&acceptorGapId=$acceptorGapId'
          '&score=$score',
    );

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error sending match request'));
    }

    return Match.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Get all matches - GET /matches
  Future<List<Match>> getAll() async {
    final res = await ApiClient.get('/matches');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting matches'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Match.fromJson(json)).toList();
  }

  // Get a match by id - GET /matches/{id}
  Future<Match> getById(int id) async {
    final res = await ApiClient.get('/matches/$id');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting match'));
    }

    return Match.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Pending requests received by the user - GET /matches/user/{userId}/pending
  Future<List<Match>> getPendingReceived(int userId) async {
    final res = await ApiClient.get('/matches/user/$userId/pending');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting pending matches'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Match.fromJson(json)).toList();
  }

  // Accept a match request - PATCH /matches/{id}/accept?userId=
  Future<Match> accept(int matchId, int userId) async {
    final res = await ApiClient.patch('/matches/$matchId/accept?userId=$userId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error accepting match'));
    }

    return Match.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Reject a match request - PATCH /matches/{id}/reject?userId=
  Future<Match> reject(int matchId, int userId) async {
    final res = await ApiClient.patch('/matches/$matchId/reject?userId=$userId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error rejecting match'));
    }

    return Match.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Mark an accepted match as completed - PATCH /matches/{id}/complete
  Future<Match> complete(int matchId) async {
    final res = await ApiClient.patch('/matches/$matchId/complete');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error completing match'));
    }

    return Match.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // The back sends business errors as plain text (400/404/409) or as JSON {"error": "..."} (409)
  String _errorMessage(dynamic res, String fallback) {
    final body = utf8.decode(res.bodyBytes).trim();
    if (body.isEmpty) return '$fallback: ${res.statusCode}';

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // No es JSON, es texto plano
    }
    return body;
  }
}