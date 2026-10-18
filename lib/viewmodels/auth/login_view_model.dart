import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';

// State and logic of the log in screen
class LoginViewModel extends ChangeNotifier {
  final AuthService _authService;

  LoginViewModel({AuthService? authService}) : _authService = authService ?? AuthService();

  bool _isLoading = false;
  String? _errorMessage;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

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
    _isLoading = true;
    _errorMessage = null;
    _notify();

    try {
      await _authService.login(email, password);
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      _notify();
    }
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
