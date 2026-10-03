import 'dart:convert';
import '../core/api_client.dart';
import '../models/google_auth_url_response.dart';

class GoogleService {
  // Pide la URL de autorización de Google - GET /google/auth-url
  Future<String> getAuthUrl() async {
    final res = await ApiClient.get('/google/auth-url');

    if (res.statusCode != 200) {
      throw Exception('Error al obtener la URL de Google: ${res.statusCode}');
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
      throw Exception('Error al importar el horario: ${res.statusCode}');
    }

    return true;
  }
}
