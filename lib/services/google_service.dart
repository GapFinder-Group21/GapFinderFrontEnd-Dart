import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/models/responses/google_auth_url_response.dart';

class GoogleService {
  // Pide la URL de autorización de Google - GET /google/auth-url
  Future<String> getAuthUrl() async {
    final res = await ApiClient.get('/google/auth-url');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error al obtener la URL de Google'));
    }

    final data = GoogleAuthUrlResponse.fromJson(
      jsonDecode(utf8.decode(res.bodyBytes)),
    );
    return data.url;
  }

  // Importa el horario desde Google Calendar - POST /google/import-schedule
  Future<bool> importSchedule() async {
    final res = await ApiClient.post('/google/import-schedule');

    if (res.statusCode != 200) {
      // The status code stays in the message: the import screen treats a 409 as success
      throw Exception('Error al importar el horario: ${res.statusCode}');
    }

    return true;
  }

  // The back sends errors as plain text (400/403/404/409) or as JSON {"error": "..."} (409)
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
}
