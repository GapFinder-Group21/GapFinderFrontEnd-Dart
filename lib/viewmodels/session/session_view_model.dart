import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';

// Decides if the app opens on /home or on /welcome
class SessionViewModel extends ChangeNotifier {
  bool? _hasSession;
  bool _disposed = false;

  // null while it is still checking
  bool? get hasSession => _hasSession;

  // Checks if there is a saved session
  Future<void> init() async {
    _hasSession = await TokenStorage.hasSession();
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
