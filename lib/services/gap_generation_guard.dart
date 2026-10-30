import 'package:shared_preferences/shared_preferences.dart';

// The app asks the back to recalculate the week gaps (POST /gaps/user/{userId}/generate-week) at most once
// per day for each user, and again after the class blocks change. Asking on every refresh (init, reconnect,
// every tap on the Schedule tab) is useless work, and a recalculation can change the gaps under the
// screens that already use them.
class GapGenerationGuard {
  static String _key(int userId) => 'gaps_generated_on_$userId';

  static String _dayOf(DateTime now) =>
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  // True when the gaps of this user were not recalculated today (or the class blocks changed since)
  static Future<bool> isDue(int userId, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_key(userId)) != _dayOf(now ?? DateTime.now());
    } catch (_) {
      return true; // if it cannot be read, it is safer to recalculate
    }
  }

  // Call it after the back recalculated the gaps
  static Future<void> markDone(int userId, {DateTime? now}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key(userId), _dayOf(now ?? DateTime.now()));
    } catch (_) {
      // Not saving it only means one extra recalculation
    }
  }

  // For changes where the user id is not at hand: every saved day is forgotten
  static Future<void> invalidateAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where((k) => k.startsWith('gaps_generated_on_')).toList()) {
        await prefs.remove(key);
      }
    } catch (_) {
      // Nothing to do
    }
  }

  // Call it when the class blocks of the user change: the next refresh recalculates the gaps
  static Future<void> invalidate(int userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_key(userId));
    } catch (_) {
      // Nothing to do
    }
  }
}
