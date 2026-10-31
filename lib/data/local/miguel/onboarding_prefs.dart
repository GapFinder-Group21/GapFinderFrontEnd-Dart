import 'package:shared_preferences/shared_preferences.dart';

// Steps of the onboarding, in order
enum OnboardingStep {
  register('register'),
  interests('interests'),
  scheduleSetup('schedule_setup'),
  done('done');

  final String value;
  const OnboardingStep(this.value);

  static OnboardingStep? fromValue(String? value) {
    for (final step in values) {
      if (step.value == value) return step;
    }
    return null;
  }
}

// The step of the onboarding where each user is (SharedPreferences key onboarding_step:<userId>).
// It is saved per user: a second account on the same phone never inherits the step of the first one.
class OnboardingPrefs {
  // The key used before the step was saved per user; it is removed when a step is written or cleared
  static const legacyKey = 'onboarding_step';

  static String keyFor(int userId) => 'onboarding_step:$userId';

  // Saves the step only if it is ahead of the saved one, so a screen opened again never goes backwards
  Future<void> advanceTo(int userId, OnboardingStep step) async {
    final prefs = await SharedPreferences.getInstance();
    final current = OnboardingStep.fromValue(prefs.getString(keyFor(userId)));
    if (current != null && current.index >= step.index) return;
    await prefs.setString(keyFor(userId), step.value);
    await prefs.remove(legacyKey);
  }

  // A new account starts the onboarding from the interests, whatever was saved before for that id
  Future<void> start(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyFor(userId), OnboardingStep.interests.value);
    await prefs.remove(legacyKey);
  }

  // The step of the user (null if there is none: an account that never did the onboarding on this phone)
  Future<OnboardingStep?> get(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingStep.fromValue(prefs.getString(keyFor(userId)));
  }

  // Forgets the step of the user (logout)
  Future<void> clear(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyFor(userId));
    await prefs.remove(legacyKey);
  }
}
