// The only place where the address of the server is written.
// Every request, the connection check and the avatars read ApiConfig.baseUrl.
//
// The default address points to our public AWS server with HTTPS.
// To use a different backend, override it with --dart-define:
//
// flutter run --dart-define=API_BASE_URL=https://54-226-15-64.sslip.io
// flutter build apk --release --dart-define=API_BASE_URL=https://54-226-15-64.sslip.io

class ApiConfig {
  // Public AWS EC2 backend with HTTPS.
  // Builds without --dart-define automatically use this server.
  static const String defaultBaseUrl =
      'https://54-226-15-64.sslip.io';

  // Allows overriding the server address at build time.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: defaultBaseUrl,
  );
}