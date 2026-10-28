import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/google_import_store.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/services/google_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// Steps of the Google Calendar import (offline: there is no connection, so nothing is tried)
enum GoogleImportPhase { connecting, success, error, offline }

// State and logic of the Google Calendar import screen (network only: the import needs the back)
class GoogleCalendarViewModel extends ChangeNotifier with OfflineAwareMixin {
  static const offlineTitle = 'Importar tu horario necesita conexión';
  static const offlineBanner = 'Sin conexión · no se puede importar tu horario';

  // The import is long, but the spinner never lasts longer than this
  static const importTimeout = Duration(seconds: 30);

  final GoogleService _googleService;
  final MiguelLocalCache _localCache;

  GoogleCalendarViewModel({GoogleService? googleService, MiguelLocalCache? localCache})
      : _googleService = googleService ?? GoogleService(),
        _localCache = localCache ?? MiguelLocalCache.instance;

  GoogleImportPhase _phase = GoogleImportPhase.connecting;
  String? _errorMessage;
  GoogleImportState? _lastImport;
  bool _disposed = false;

  GoogleImportPhase get phase => _phase;
  String? get errorMessage => _errorMessage;

  // How the last import ended, read from the saved file (null if there was none)
  GoogleImportState? get lastImport => _lastImport;

  // The Retry button works only when the connection is back
  bool get canRetry => !isOffline;

  // Start the import as soon as the screen opens; without internet it only shows the saved state.
  // When the connection comes back the Retry button turns on (the import is the user's choice).
  Future<void> init() {
    listenToConnectivity(onRestored: () async {});
    return importSchedule();
  }

  // Asks the backend to import the schedule - POST /google/import-schedule
  Future<void> importSchedule() async {
    _errorMessage = null;

    if (!hasConnection) {
      await _showOffline();
      return;
    }

    _phase = GoogleImportPhase.connecting;
    _notify();

    try {
      debugPrint('🚀 IMPORT: Starting Google Calendar import...');
      await _googleService.importSchedule().timeout(importTimeout);
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

      // The network failed: nothing was imported, so the saved state is shown
      if (isNetworkError(e)) {
        await _showOffline();
        return;
      }

      _localCache.saveGoogleImport(success: false, message: e.toString());
      _phase = GoogleImportPhase.error;
      _errorMessage = e.toString();
      _notify();
    }
  }

  // Shows that the import needs internet, with the state of the last import saved in the file
  Future<void> _showOffline() async {
    try {
      _lastImport = await _localCache.googleImport.get();
    } catch (e) {
      debugPrint('Could not read the last import: $e');
    }
    if (_disposed) return;
    _phase = GoogleImportPhase.offline;
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
