import 'package:shared_preferences/shared_preferences.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';

// STORAGE MIGUEL: SharedPreferences (preferred study duration per user)
// The duration the user chose the last time (SharedPreferences key study_default_minutes:<userId>), so
// the chip is already selected the next time the screen opens. It is saved per user: a second account on
// the same phone never inherits it. The value is the minutes; 0 means "hasta que termine el gap".
class StudyModePrefs {
  static const keyPrefix = 'study_default_minutes:';

  static String keyFor(int userId) => '$keyPrefix$userId';

  Future<StudyDuration?> get(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return StudyDuration.fromMinutes(prefs.getInt(keyFor(userId)));
  }

  Future<void> set(int userId, StudyDuration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(keyFor(userId), duration.minutes);
  }

  // Forgets the preference of the user (logout)
  Future<void> clear(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(keyFor(userId));
  }

  // Forgets the preference of every user (logout when the session expired and the user is not known)
  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    for (final key in prefs.getKeys().where((k) => k.startsWith(keyPrefix)).toList()) {
      await prefs.remove(key);
    }
  }
}
