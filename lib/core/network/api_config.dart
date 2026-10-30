// The only place where the address of the server is written.
// Every request, the connection check and the avatars read ApiConfig.baseUrl.
// Build with the real address:
//   flutter run --dart-define=API_BASE_URL=https://<domain>
//   flutter build apk --release --dart-define=API_BASE_URL=https://<domain>
class ApiConfig {
  // Placeholder until the public address of the server is decided: it never answers on purpose,
  // so a build made without --dart-define is easy to notice
  static const String defaultBaseUrl = 'https://CAMBIAR-POR-EL-DOMINIO-DEL-SERVIDOR.invalid';

  static const String baseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: defaultBaseUrl);
}
