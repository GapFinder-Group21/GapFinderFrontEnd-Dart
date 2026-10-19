import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// State of the welcome screen. It works without internet: it only knows if there is a connection
// and if a session is saved, to decide whether the offline notice is shown.
class WelcomeViewModel extends ChangeNotifier with OfflineAwareMixin {
  bool _hasSession = false;
  bool _disposed = false;

  // Without connection and without a saved session the user cannot sign up or log in yet
  bool get showOfflineNotice => isOffline && !_hasSession;

  // Starts listening to the connection and reads the saved session
  Future<void> init() async {
    listenToConnectivity(onRestored: _loadSession);
    await _loadSession();
  }

  Future<void> _loadSession() async {
    try {
      _hasSession = await TokenStorage.hasSession();
    } catch (e) {
      debugPrint('No se pudo leer la sesión guardada: $e');
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
