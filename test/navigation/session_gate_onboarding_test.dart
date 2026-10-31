import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/services/session_cleanup.dart';
import 'package:gapfinderfrontend_dart/viewmodels/session/session_view_model.dart';

import '../viewmodels/secure_storage_mock.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final storage = SecureStorageMock();
  late OnboardingPrefs prefs;

  setUp(() {
    storage.install();
    SharedPreferences.setMockInitialValues({});
    prefs = OnboardingPrefs();
  });

  tearDown(() => storage.uninstall());

  void logIn(int userId) {
    storage.setUserId(userId);
    storage.values['refreshToken'] = 'r';
  }

  Future<SessionViewModel> openApp() async {
    final vm = SessionViewModel();
    await vm.init();
    return vm;
  }

  group('the app resumes the onboarding', () {
    test('closing the app at the interests opens the interests, not the home', () async {
      logIn(1);
      await prefs.advanceTo(1, OnboardingStep.interests);

      final vm = await openApp();

      expect(vm.hasSession, isTrue);
      expect(vm.resumeRoute, AppRoutes.interests);
    });

    test('closing the app at the schedule setup opens the schedule setup', () async {
      logIn(1);
      await prefs.advanceTo(1, OnboardingStep.scheduleSetup);

      expect((await openApp()).resumeRoute, AppRoutes.scheduleSetup);
    });

    test('a finished onboarding, or an account with no step, opens the home', () async {
      logIn(1);
      await prefs.advanceTo(1, OnboardingStep.done);
      expect((await openApp()).resumeRoute, isNull);

      logIn(2); // an account that never did the onboarding on this phone
      expect((await openApp()).resumeRoute, isNull);
    });

    test('without a session it goes to the welcome and has nothing to resume', () async {
      final vm = await openApp();

      expect(vm.hasSession, isFalse);
      expect(vm.resumeRoute, isNull);
    });
  });

  group('the step belongs to each user', () {
    test('a second account on the same phone does not inherit the "done" of the first one', () async {
      await prefs.advanceTo(1, OnboardingStep.done);

      expect(await prefs.get(1), OnboardingStep.done);
      expect(await prefs.get(2), isNull);
    });

    test('the step saved before it was per user is ignored', () async {
      SharedPreferences.setMockInitialValues({'onboarding_step': 'done'});

      expect(await OnboardingPrefs().get(1), isNull);

      await OnboardingPrefs().advanceTo(1, OnboardingStep.interests);
      expect((await SharedPreferences.getInstance()).containsKey('onboarding_step'), isFalse);
    });

    test('a new account starts at the interests even if that id had "done" saved', () async {
      await prefs.advanceTo(3, OnboardingStep.done);

      await prefs.start(3);

      expect(await prefs.get(3), OnboardingStep.interests);
    });

    test('the logout forgets the step of that user and no other', () async {
      await prefs.advanceTo(1, OnboardingStep.scheduleSetup);
      await prefs.advanceTo(2, OnboardingStep.interests);

      final step = SessionCleanup.stepsFor(1).firstWhere((s) => s.name == 'onboarding step');
      await step.action();

      expect(await prefs.get(1), isNull);
      expect(await prefs.get(2), OnboardingStep.interests);
    });
  });
}
