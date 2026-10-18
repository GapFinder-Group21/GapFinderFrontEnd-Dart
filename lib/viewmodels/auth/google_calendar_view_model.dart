import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/services/google_service.dart';

// Steps of the Google Calendar import
enum GoogleImportPhase { connecting, success, error }

// State and logic of the Google Calendar import screen
class GoogleCalendarViewModel extends ChangeNotifier {
  final GoogleService _googleService;

  GoogleCalendarViewModel({GoogleService? googleService})
      : _googleService = googleService ?? GoogleService();

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
      if (_disposed) return;
      _phase = GoogleImportPhase.success;
      _notify();
    } catch (e) {
      debugPrint('⚠️ IMPORT ERROR/CONFLICT: $e');
      if (_disposed) return;

      // A 409 means the classes were already imported, so it counts as success
      if (e.toString().contains('409')) {
        debugPrint('ℹ️ IMPORT: Conflict 409 detected, but data persists. Marking as success.');
        _phase = GoogleImportPhase.success;
        _notify();
        return;
      }

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
