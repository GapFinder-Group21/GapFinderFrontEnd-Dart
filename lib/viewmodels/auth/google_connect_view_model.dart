import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/services/google_service.dart';

// State and logic of the "connect Google" screen (network only: Google sign-in needs the back)
class GoogleConnectViewModel extends ChangeNotifier {
  // The spinner never lasts longer than this
  static const requestTimeout = Duration(seconds: 15);

  final GoogleService _googleService;
  final ConnectivityService _connectivity;

  GoogleConnectViewModel({GoogleService? googleService, ConnectivityService? connectivity})
      : _googleService = googleService ?? GoogleService(),
        _connectivity = connectivity ?? ConnectivityService.instance {
    _isOffline = !_connectivity.isOnline;
    _connectivitySub = _connectivity.onStatusChange.listen((online) {
      _isOffline = !online;
      if (online) _error = null;
      _notify();
    });
  }

  StreamSubscription<bool>? _connectivitySub;
  bool _isOffline = false;
  bool _loading = false;
  bool _opened = false;
  String? _error;
  bool _disposed = false;

  bool get isOffline => _isOffline;
  bool get loading => _loading;
  bool get opened => _opened;
  String? get error => _error;

  // Gets the Google sign-in URL from the backend and opens it in the browser - GET /google/auth-url
  Future<void> openGoogleAuth() async {
    if (_isOffline) return;
    _loading = true;
    _error = null;
    _notify();

    try {
      final authUrl = await _googleService.getAuthUrl().timeout(requestTimeout);
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
    _connectivitySub?.cancel();
    super.dispose();
  }
}
