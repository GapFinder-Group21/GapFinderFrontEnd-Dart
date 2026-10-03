import 'dart:convert';
import '../core/api_client.dart';
import '../models/gap.dart';

class GapService {
  // Get all gaps (de todos los usuarios) - GET /gaps
  Future<List<Gap>> getGaps() async {
    final res = await ApiClient.get('/gaps');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting gaps'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Gap.fromJson(json)).toList();
  }

  // Gaps of one user, filtered on the client (no hay endpoint por usuario)
  Future<List<Gap>> getGapsByUser(int userId) async {
    final all = await getGaps();
    return all.where((g) => g.userId == userId).toList();
  }

  // Get a gap by id - GET /gaps/{id}
  Future<Gap> getGap(int id) async {
    final res = await ApiClient.get('/gaps/$id');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting gap'));
    }

    return Gap.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Calculate and save the gaps of a user's week from their class schedule
  // POST /gaps/user/{userId}/generate-week?weekStart=2026-09-28
  // weekStart debe ser lunes; si se omite, el back usa la semana actual
  // (o la siguiente si hoy es domingo)
  Future<List<Gap>> generateWeek(int userId, {DateTime? weekStart}) async {
    final query = weekStart != null ? '?weekStart=${_formatDate(weekStart)}' : '';
    final res = await ApiClient.post('/gaps/user/$userId/generate-week$query');

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error generating week gaps'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Gap.fromJson(json)).toList();
  }

  // Create a gap for a user - POST /gaps
  Future<Gap> createGap(int userId, Gap gap) async {
    final res = await ApiClient.post('/gaps', body: _withUser(gap, userId));

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error creating gap'));
    }

    return Gap.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Update a gap - PUT /gaps/{id}
  Future<Gap> updateGap(int id, int userId, Gap gap) async {
    final res = await ApiClient.put('/gaps/$id', body: _withUser(gap, userId));

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating gap'));
    }

    return Gap.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Delete a gap - DELETE /gaps/{id}
  Future<void> deleteGap(int id) async {
    final res = await ApiClient.delete('/gaps/$id');

    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res, 'Error deleting gap'));
    }
  }

  // El dueño va plano (userId), como lo lee GapBasicDTO
  Map<String, dynamic> _withUser(Gap gap, int userId) {
    return {
      ...gap.toJson(),
      'userId': userId,
    };
  }

  // yyyy-MM-dd, el formato que espera weekStart
  String _formatDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  // The back sends errors as plain text (400/404/409) or as JSON {"error": "..."} (409)
  String _errorMessage(dynamic res, String fallback) {
    final body = utf8.decode(res.bodyBytes).trim();
    if (body.isEmpty) return '$fallback: ${res.statusCode}';

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // Not JSON, it is plain text
    }
    return body;
  }

  // Get the gaps of a user for a week - GET /gaps/user/{userId}
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async {
    final query = weekStart != null ? '?weekStart=$weekStart' : '';
    final res = await ApiClient.get('/gaps/user/$userId$query');

    if (res.statusCode != 200) {
      throw Exception('Error getting user gaps: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Gap.fromJson(json)).toList();
  }
}