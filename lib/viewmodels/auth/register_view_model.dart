import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/constants/careers.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/register_draft_store.dart';
import 'package:gapfinderfrontend_dart/models/enums/effort_type_enum.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// State and logic of the sign up form (network only to send it; the form works without internet)
class RegisterViewModel extends ChangeNotifier with OfflineAwareMixin {
  // Shown by the banner and by the error when there is no connection
  static const offlineMessage = 'Necesitas conexión para crear tu cuenta; no perderás lo que escribiste';

  // The sign up request never keeps the screen loading longer than this
  static const requestTimeout = Duration(seconds: 15);

  final AuthService _authService;
  final MiguelLocalCache _localCache;

  RegisterViewModel({AuthService? authService, MiguelLocalCache? localCache})
      : _authService = authService ?? AuthService(),
        _localCache = localCache ?? MiguelLocalCache.instance;

  // What the user has typed so far (the password is never kept here or saved)
  String _draftName = '';
  String _draftEmail = '';
  String _draftSemester = '';

  String? _selectedCareer = careers.first;
  EffortTypeEnum _selectedEffort = EffortTypeEnum.MEDIUM;
  bool _isLoading = false;
  String? _errorMessage;
  bool _disposed = false;

  // Starts listening to the connection; the form itself needs nothing from the network
  void init() {
    listenToConnectivity(onRestored: () async {});
  }

  // The Retry button: checks the connection for real (the listener updates isOffline)
  Future<void> retryConnection() => ConnectivityService.instance.checkNow();

  // The draft saved in Hive, to fill the form again when the user comes back; null if there is none
  Future<RegisterDraft?> restoreDraft() async {
    try {
      final draft = await _localCache.registerDraft.get();
      if (draft == null) return null;

      _draftName = draft.name;
      _draftEmail = draft.email;
      _draftSemester = draft.semester;
      if (draft.career != null && careers.contains(draft.career)) _selectedCareer = draft.career;
      _notify();
      return draft;
    } catch (e) {
      debugPrint('Could not read the register draft: $e');
      return null;
    }
  }

  String? get selectedCareer => _selectedCareer;
  EffortTypeEnum get selectedEffort => _selectedEffort;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  void selectCareer(String? career) {
    _selectedCareer = career;
    _persistDraft();
    _notify();
  }

  // Saves in Hive what the user has typed (name, email, career and semester) while they write.
  // The password is not a parameter on purpose. It never blocks the form.
  void saveDraft({required String name, required String email, required String semesterText}) {
    _draftName = name;
    _draftEmail = email;
    _draftSemester = semesterText;
    _persistDraft();
  }

  void _persistDraft() {
    _localCache.saveRegisterDraft(RegisterDraft(
      name: _draftName,
      email: _draftEmail,
      career: _selectedCareer,
      semester: _draftSemester,
    ));
    _localCache.advanceOnboarding(OnboardingStep.register);
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

    // Nothing is sent without internet, and the draft stays where it is
    if (isOffline) {
      return _fail(offlineMessage);
    }

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
      await _authService
          .register(
            name: name,
            email: email,
            password: password,
            career: _selectedCareer!,
            semester: semester,
            preferredEffort: _selectedEffort,
            phoneNumber: normalizedPhone,
          )
          .timeout(requestTimeout);
      // The account exists: the draft is not needed anymore and the next step is the interests
      _localCache.clearRegisterDraft();
      _localCache.advanceOnboarding(OnboardingStep.interests);
      return true;
    } catch (e) {
      _errorMessage = isNetworkError(e) ? offlineMessage : e.toString().replaceAll('Exception: ', '');
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
