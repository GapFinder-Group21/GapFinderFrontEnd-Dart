import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gapfinderfrontend_dart/services/google_service.dart';

// State and logic of the "connect Google" screen
class GoogleConnectViewModel extends ChangeNotifier {
  final GoogleService _googleService;

  GoogleConnectViewModel({GoogleService? googleService})
      : _googleService = googleService ?? GoogleService();

  bool _loading = false;
  bool _opened = false;
  String? _error;
  bool _disposed = false;

  bool get loading => _loading;
  bool get opened => _opened;
  String? get error => _error;

  // Gets the Google sign-in URL from the backend and opens it in the browser - GET /google/auth-url
  Future<void> openGoogleAuth() async {
    _loading = true;
    _error = null;
    _notify();

    try {
      final authUrl = await _googleService.getAuthUrl();
      final uri = Uri.parse(authUrl);

      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        throw Exception('No se pudo abrir el navegador');
      }

      _opened = true;
      _loading = false;
    } catch (e) {
      _error = e.toString();
      _loading = false;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
