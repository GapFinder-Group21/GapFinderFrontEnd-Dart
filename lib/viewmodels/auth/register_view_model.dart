import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/constants/careers.dart';
import 'package:gapfinderfrontend_dart/models/enums/effort_type_enum.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';

// State and logic of the sign up form
class RegisterViewModel extends ChangeNotifier {
  final AuthService _authService;

  RegisterViewModel({AuthService? authService}) : _authService = authService ?? AuthService();

  String? _selectedCareer = careers.first;
  EffortTypeEnum _selectedEffort = EffortTypeEnum.MEDIUM;
  bool _isLoading = false;
  String? _errorMessage;
  bool _disposed = false;

  String? get selectedCareer => _selectedCareer;
  EffortTypeEnum get selectedEffort => _selectedEffort;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void selectCareer(String? career) {
    _selectedCareer = career;
    _notify();
  }

  void selectEffort(EffortTypeEnum effort) {
    _selectedEffort = effort;
    _notify();
  }

  // Validates every field and creates the account - POST /auth/register
  // Returns true when the account was created; otherwise errorMessage has the reason
  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String confirmPassword,
    required String semesterText,
    required String phone,
  }) async {
    _errorMessage = null;

    if (name.isEmpty) {
      return _fail('Por favor ingresa tu nombre');
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return _fail('Por favor ingresa un correo electrónico válido');
    }

    if (password.length < 8) {
      return _fail('La contraseña debe tener al menos 8 caracteres');
    }

    if (password != confirmPassword) {
      return _fail('Las contraseñas no coinciden');
    }

    final semester = int.tryParse(semesterText);
    if (semester == null || semester < 1 || semester > 12) {
      return _fail('El semestre debe ser un número entre 1 y 12');
    }

    if (_selectedCareer == null) {
      return _fail('Por favor selecciona una carrera');
    }

    if (phone.isEmpty) {
      return _fail('Por favor ingresa tu número de teléfono');
    }

    // Same rule as the backend: optional + and 7 to 15 digits
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\+?\d{7,15}$').hasMatch(normalizedPhone)) {
      return _fail('El teléfono debe tener de 7 a 15 dígitos (puede empezar con +)');
    }

    _isLoading = true;
    _notify();

    try {
      await _authService.register(
        name: name,
        email: email,
        password: password,
        career: _selectedCareer!,
        semester: semester,
        preferredEffort: _selectedEffort,
        phoneNumber: normalizedPhone,
      );
      return true;
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      return false;
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  bool _fail(String message) {
    _errorMessage = message;
    return false;
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
