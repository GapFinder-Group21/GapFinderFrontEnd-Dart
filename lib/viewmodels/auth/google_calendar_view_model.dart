import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/services/google_service.dart';

// Steps of the Google Calendar import
enum GoogleImportPhase { connecting, success, error }

// State and logic of the Google Calendar import screen
class GoogleCalendarViewModel extends ChangeNotifier {
  final GoogleService _googleService;
  final MiguelLocalCache _localCache;

  GoogleCalendarViewModel({GoogleService? googleService, MiguelLocalCache? localCache})
      : _googleService = googleService ?? GoogleService(),
        _localCache = localCache ?? MiguelLocalCache.instance;

  GoogleImportPhase _phase = GoogleImportPhase.connecting;
  String? _errorMessage;
  bool _disposed = false;

  GoogleImportPhase get phase => _phase;
  String? get errorMessage => _errorMessage;

  // Start the import as soon as the screen opens
  Future<void> init() => importSchedule();

  // Asks the backend to import the schedule - POST /google/import-schedule
  Future<void> importSchedule() async {
    _phase = GoogleImportPhase.connecting;
    _errorMessage = null;
    _notify();

    try {
      debugPrint('🚀 IMPORT: Starting Google Calendar import...');
      await _googleService.importSchedule();
      debugPrint('✅ IMPORT: Success (Standard)');
      // Saved in a file how the import ended (never blocks the screen)
      _localCache.saveGoogleImport(success: true, message: 'Schedule imported');
      _localCache.advanceOnboarding(OnboardingStep.done);
      if (_disposed) return;
      _phase = GoogleImportPhase.success;
      _notify();
    } catch (e) {
      debugPrint('⚠️ IMPORT ERROR/CONFLICT: $e');
      if (_disposed) return;

      // A 409 means the classes were already imported, so it counts as success
      if (e.toString().contains('409')) {
        debugPrint('ℹ️ IMPORT: Conflict 409 detected, but data persists. Marking as success.');
        _localCache.saveGoogleImport(success: true, message: 'The classes were already imported');
        _localCache.advanceOnboarding(OnboardingStep.done);
        _phase = GoogleImportPhase.success;
        _notify();
        return;
      }

      _localCache.saveGoogleImport(success: false, message: e.toString());
      _phase = GoogleImportPhase.error;
      _errorMessage = e.toString();
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
