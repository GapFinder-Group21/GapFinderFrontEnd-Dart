import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';

// Decides if the app opens on /home, on the onboarding step the user left or on /welcome
class SessionViewModel extends ChangeNotifier {
  final OnboardingPrefs _onboarding;

  SessionViewModel({OnboardingPrefs? onboarding}) : _onboarding = onboarding ?? OnboardingPrefs();

  bool? _hasSession;
  String? _resumeRoute;
  bool _disposed = false;

  // null while it is still checking
  bool? get hasSession => _hasSession;

  // The onboarding screen to open when the user closed the app in the middle of it (null: go to /home)
  String? get resumeRoute => _resumeRoute;

  // Checks if there is a saved session and, if there is, the onboarding step of that user
  Future<void> init() async {
    final hasSession = await TokenStorage.hasSession();
    if (hasSession) _resumeRoute = await _readResumeRoute();
    _hasSession = hasSession;
    _notify();
  }

  Future<String?> _readResumeRoute() async {
    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return null;
      return routeFor(await _onboarding.get(userId));
    } catch (e) {
      debugPrint('Could not read the onboarding step: $e');
      return null;
    }
  }

  // The screen of a step. No step (an account that never did the onboarding here) or done: no resume.
  static String? routeFor(OnboardingStep? step) {
    switch (step) {
      case OnboardingStep.register:
      case OnboardingStep.interests:
        return AppRoutes.interests;
      case OnboardingStep.scheduleSetup:
        return AppRoutes.scheduleSetup;
      case OnboardingStep.done:
      case null:
        return null;
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
