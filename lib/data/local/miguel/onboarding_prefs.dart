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

// The step of the onboarding where the user is (SharedPreferences key onboarding_step)
class OnboardingPrefs {
  static const key = 'onboarding_step';

  // Saves the step only if it is ahead of the saved one, so a screen opened again never goes backwards
  Future<void> advanceTo(OnboardingStep step) async {
    final prefs = await SharedPreferences.getInstance();
    final current = OnboardingStep.fromValue(prefs.getString(key));
    if (current != null && current.index >= step.index) return;
    await prefs.setString(key, step.value);
  }

  Future<OnboardingStep?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return OnboardingStep.fromValue(prefs.getString(key));
  }
}
