import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/api_config.dart';
import '../core/token_storage.dart';
import '../core/api_client.dart';
import '../models/auth_response.dart';
import '../models/effort_type_enum.dart';

class AuthService {
  final String _url = '${ApiConfig.baseUrl}/auth';

  // Registra un usuario nuevo y guarda los tokens - POST /auth/register
  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
    required String career,
    required int semester,
    required EffortTypeEnum preferredEffort,
    required String phoneNumber,
  }) async {
    final res = await _post(
      Uri.parse('$_url/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'email': email.toLowerCase(),
        'password': password,
        'career': career,
        'semester': semester,
        'preferredEffort': preferredEffort.toJson(),
        'phoneNumber': phoneNumber,
      }),
    );

    if (res.statusCode != 201 && res.statusCode != 200) {
      if (res.statusCode == 409) {
        throw Exception(_errorMessage(res, 'Ya existe una cuenta con ese correo'));
      }
      throw Exception(_errorMessage(res, 'Error al registrarse: ${res.statusCode}'));
    }

    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      if (decoded['accessToken'] != null) {
        final authResponse = AuthResponse.fromJson(decoded);
        await TokenStorage.saveSession(authResponse.accessToken, authResponse.refreshToken, authResponse.id);
        return authResponse;
      }
    } catch (_) {
      // Si el formato no trae tokens directos
    }

    // Si el registro no devolvió tokens, realizamos login automático
    return await login(email, password);
  }

  // Inicia sesión y guarda los tokens - POST /auth/login
  Future<AuthResponse> login(String email, String password) async {
    final res = await _post(
      Uri.parse('$_url/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'email': email.toLowerCase(), 'password': password}),
    );

    // El back responde 401/403 cuando el correo o la contraseña no coinciden
    if (res.statusCode == 401 || res.statusCode == 403) {
      throw Exception('Correo o contraseña incorrectos');
    }
    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error al iniciar sesión: ${res.statusCode}'));
    }

    final authResponse = AuthResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    await TokenStorage.saveSession(authResponse.accessToken, authResponse.refreshToken, authResponse.id);
    return authResponse;
  }

  // Pide un access token nuevo usando el refresh token guardado - POST /auth/refresh
  Future<AuthResponse> refresh() async {
    final refreshToken = await TokenStorage.getRefreshToken();

    final res = await http.post(
      Uri.parse('$_url/refresh'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'refreshToken': refreshToken}),
    );

    if (res.statusCode != 200) {
      throw Exception('Error al refrescar la sesión: ${res.statusCode}');
    }

    final authResponse = AuthResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    await TokenStorage.saveSession(authResponse.accessToken, authResponse.refreshToken, authResponse.id);
    return authResponse;
  }

  // Cierra sesión en el back y borra los tokens locales - POST /auth/logout
  // Aunque el back no responda, la sesión local se borra igual
  Future<void> logout() async {
    try {
      await ApiClient.post('/auth/logout');
    } catch (_) {
      // Sin conexión: el refresh token queda vivo en el back hasta que venza
    } finally {
      await TokenStorage.clear();
    }
  }

  // POST sin token; si el back no responde, se muestra un mensaje claro en vez del error de socket
  Future<http.Response> _post(Uri uri, {Map<String, String>? headers, Object? body}) async {
    try {
      return await http.post(uri, headers: headers, body: body);
    } catch (_) {
      throw Exception('No se pudo conectar con el servidor');
    }
  }

  // El back manda los errores como texto plano, como {"error"|"message": "..."}
  // o, en validaciones, como {"campo": "mensaje"}
  String _errorMessage(http.Response res, String fallback) {
    final body = utf8.decode(res.bodyBytes).trim();
    if (body.isEmpty) return fallback;

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        // Error por defecto de Spring: "error" es solo "Bad Request", el detalle va en "message"
        if (decoded.containsKey('path')) {
          final message = decoded['message']?.toString() ?? '';
          return message.isNotEmpty ? message : fallback;
        }
        final message = decoded['error'] ?? decoded['message'];
        if (message != null) return message.toString();
        if (decoded.isNotEmpty) return decoded.values.join('\n');
      }
      if (decoded is String) return decoded;
    } catch (_) {
      // No es JSON, es texto plano
    }
    return body.startsWith('<') ? fallback : body;
  }
}
