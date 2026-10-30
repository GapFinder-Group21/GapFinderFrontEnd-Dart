import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:gapfinderfrontend_dart/core/network/api_config.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/navigation/navigator_key.dart'; // Para acceder al navigatorKey
import 'package:gapfinderfrontend_dart/services/session_cleanup.dart';

class ApiClient {
  // GET autenticado
  static Future<http.Response> get(String path) async {
    return _sendWithAuth((headers) => http.get(Uri.parse('${ApiConfig.baseUrl}$path'), headers: headers));
  }

  // POST autenticado
  static Future<http.Response> post(String path, {Object? body}) async {
    return _sendWithAuth((headers) => http.post(
          Uri.parse('${ApiConfig.baseUrl}$path'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  // PUT autenticado
  static Future<http.Response> put(String path, {Object? body}) async {
    return _sendWithAuth((headers) => http.put(
          Uri.parse('${ApiConfig.baseUrl}$path'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  // PATCH autenticado
  static Future<http.Response> patch(String path, {Object? body}) async {
    return _sendWithAuth((headers) => http.patch(
          Uri.parse('${ApiConfig.baseUrl}$path'),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: body != null ? jsonEncode(body) : null,
        ));
  }

  // POST autenticado con multipart/form-data (campos de texto y archivos)
  // La petición se arma dentro del callback porque un multipart no se puede reenviar tras refrescar el token
  static Future<http.Response> postMultipart(
    String path, {
    Future<List<http.MultipartFile>> Function()? files,
  }) async {
    return _sendWithAuth((headers) async {
      final request = http.MultipartRequest('POST', Uri.parse('${ApiConfig.baseUrl}$path'))
        ..headers.addAll(headers);
      if (files != null) request.files.addAll(await files());
      return http.Response.fromStream(await request.send());
    });
  }

  // DELETE autenticado
  static Future<http.Response> delete(String path) async {
    return _sendWithAuth((headers) => http.delete(Uri.parse('${ApiConfig.baseUrl}$path'), headers: headers));
  }

  // Manda la petición con el token, y si da 401 o 403, refresca y reintenta una vez
  static Future<http.Response> _sendWithAuth(
    Future<http.Response> Function(Map<String, String> headers) request,
  ) async {
    final accessToken = await TokenStorage.getAccessToken();
    var res = await request({'Authorization': 'Bearer $accessToken'});

    // El back responde 403 (no 401) cuando el token vence, así que se cubren los dos
    if (res.statusCode == 401 || res.statusCode == 403) {
      final refreshed = await _refreshAccessToken();
      if (refreshed != null) {
        res = await request({'Authorization': 'Bearer $refreshed'});
      } else {
        // El refresh token tampoco sirve: la sesión ya no es válida
        _forceLogout();
      }
      // Si con el token nuevo sigue en 403 es un tema de permisos, no de sesión,
      // así que se devuelve la respuesta y el service muestra el error
    }

    return res;
  }

  static Future<void> _forceLogout() async {
    print('🚨 SESSION EXPIRED: Forced logout triggered (401/403)');
    // The user is read first because clearing the tokens removes it
    final userId = await TokenStorage.getUserId();
    await TokenStorage.clear();
    // The same cleanup as the logout button: reminders, pending actions, caches and saved data of that user
    await SessionCleanup.run(userId);
    
    // Importamos dinámicamente o usamos la llave global para navegar sin context
    final navigator = navigatorKey.currentState;
    if (navigator != null) {
      navigator.pushNamedAndRemoveUntil('/welcome', (route) => false);
    }
  }

  // Pide un access token nuevo usando el refresh token guardado
  static Future<String?> _refreshAccessToken() async {
    final refreshToken = await TokenStorage.getRefreshToken();
    if (refreshToken == null) return null;

    final res = await http.post(
      Uri.parse('${ApiConfig.baseUrl}/auth/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );

    if (res.statusCode != 200) {
      await TokenStorage.clear(); // refresh token también inválido, cerrar sesión
      return null;
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    final newAccessToken = data['accessToken'] ?? data['token'] ?? data['jwt'];
    if (newAccessToken == null) return null;
    await TokenStorage.updateAccessToken(newAccessToken);
    return newAccessToken;
  }
}
