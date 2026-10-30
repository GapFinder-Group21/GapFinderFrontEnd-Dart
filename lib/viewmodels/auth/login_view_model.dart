import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';

// State and logic of the log in screen (network only: logging in needs the back)
class LoginViewModel extends ChangeNotifier {
  // The spinner never lasts longer than this
  static const loginTimeout = Duration(seconds: 15);

  final AuthService _authService;
  final UserService _userService;
  final JoelLocalCache _localCache;
  final ConnectivityService _connectivity;

  LoginViewModel({
    AuthService? authService,
    UserService? userService,
    JoelLocalCache? localCache,
    ConnectivityService? connectivity,
  })  : _authService = authService ?? AuthService(),
        _userService = userService ?? UserService(),
        _localCache = localCache ?? JoelLocalCache.instance,
        _connectivity = connectivity ?? ConnectivityService.instance {
    _isOffline = !_connectivity.isOnline;
    _connectivitySub = _connectivity.onStatusChange.listen(_onConnectivityChanged);
  }

  StreamSubscription<bool>? _connectivitySub;
  bool _isOffline = false;
  bool _isCheckingConnection = false;
  bool _isLoading = false;
  String? _errorMessage;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isOffline => _isOffline;
  // True while "Reintentar" is checking the connection
  bool get isCheckingConnection => _isCheckingConnection;

  // Checks the fields; returns the message to show, or null if they are fine
  String? validate(String email, String password) {
    if (email.isEmpty || password.isEmpty) {
      return 'Please fill in all fields';
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Please enter a valid email';
    }

    return null;
  }

  // Logs in and saves the tokens on the device - POST /auth/login
  Future<bool> login(String email, String password) async {
    if (_isOffline) {
      _errorMessage = 'Necesitas conexión para iniciar sesión';
      _notify();
      return false;
    }

    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      final auth = await _authService.login(email, password).timeout(loginTimeout);
      // Cache the profile in Hive (full user if GET /users/{id} works, else the login data)
      _localCache.saveProfile(
        () => _userService.getUser(auth.id),
        User(id: auth.id, name: auth.name, email: auth.email, career: ''),
      );
      return true;
    } on TimeoutException {
      _errorMessage = 'La conexión tardó demasiado. Intenta de nuevo';
      return false;
    } catch (e) {
      _errorMessage = userMessage(e, network: 'No pudimos iniciar sesión. Intenta de nuevo');
      return false;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // "Reintentar": checks the connection for real and enables the login again if it is back
  Future<void> retryConnection() async {
    if (_isCheckingConnection) return;
    _isCheckingConnection = true;
    _notify();

    final online = await _connectivity.checkNow();
    _isCheckingConnection = false;
    _isOffline = !online;
    _notify();
  }

  void _onConnectivityChanged(bool online) {
    _isOffline = !online;
    if (online) _errorMessage = null;
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
