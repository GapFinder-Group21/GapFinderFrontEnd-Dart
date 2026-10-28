import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// State of the schedule setup step. Connecting Google needs internet; without it the user can
// leave this step for later and still enter the app.
class ScheduleSetupViewModel extends ChangeNotifier with OfflineAwareMixin {
  static const offlineBanner = 'Sin conexión · puedes importar tu horario más tarde';
  static const googleOfflineText = 'Conectar Google necesita conexión';

  final MiguelLocalCache _localCache;
  bool _disposed = false;

  ScheduleSetupViewModel({MiguelLocalCache? localCache}) : _localCache = localCache ?? MiguelLocalCache.instance;

  // The Google card is off while there is no connection
  bool get canConnectGoogle => !isOffline;

  // Starts listening to the connection (the screen has nothing to load)
  void init() {
    _localCache.advanceOnboarding(OnboardingStep.scheduleSetup);
    listenToConnectivity(onRestored: () async {});
  }

  // "Continuar más tarde": the step is saved as done and the app opens without a schedule
  void continueLater() {
    _localCache.advanceOnboarding(OnboardingStep.done);
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
