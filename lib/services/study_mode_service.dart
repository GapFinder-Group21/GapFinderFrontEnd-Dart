import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';

class StudyModeService {
  // Study periods that are active now or start later (the ones that already ended never come) -
  // GET /users/{userId}/study-mode. Turning the mode on or off goes through the outbox
  // (POST and DELETE, see StudyModeOutbox), so it also works without internet.
  Future<List<StudyPeriod>> getPeriods(int userId) async {
    final res = await ApiClient.get('/users/$userId/study-mode');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'No pudimos cargar tu modo estudio'));
    }

    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    return list.map((json) => StudyPeriod.fromServer(json as Map<String, dynamic>)).toList();
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
