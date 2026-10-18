import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  static const _storage = FlutterSecureStorage();
  static const _accessKey = 'accessToken';
  static const _refreshKey = 'refreshToken';
  static const _userIdKey = 'userId';

  // Guarda tokens + userId tras login/registro/refresh
  static Future<void> saveSession(String accessToken, String refreshToken, int userId) async {
    await _storage.write(key: _accessKey, value: accessToken);
    await _storage.write(key: _refreshKey, value: refreshToken);
    await _storage.write(key: _userIdKey, value: userId.toString());
  }

  // Actualiza solo el access token (tras un refresh exitoso, el userId no cambia)
  static Future<void> updateAccessToken(String accessToken) async {
    await _storage.write(key: _accessKey, value: accessToken);
  }

  static Future<String?> getAccessToken() => _storage.read(key: _accessKey);
  static Future<String?> getRefreshToken() => _storage.read(key: _refreshKey);

  static Future<int?> getUserId() async {
    final value = await _storage.read(key: _userIdKey);
    return value != null ? int.tryParse(value) : null;
  }

  // Revisa si hay sesión guardada
  static Future<bool> hasSession() async {
    return await getRefreshToken() != null;
  }

  // Borra tokens y userId (logout)
  static Future<void> clear() async {
    await _storage.delete(key: _accessKey);
    await _storage.delete(key: _refreshKey);
    await _storage.delete(key: _userIdKey);
  }
}