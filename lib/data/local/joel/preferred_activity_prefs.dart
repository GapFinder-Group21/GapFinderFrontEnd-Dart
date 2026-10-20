import 'package:shared_preferences/shared_preferences.dart';

// Last preferred activity of each user (SharedPreferences key preferred_activity_<userId>).
// It is one small number, so SharedPreferences is enough, and it lets the wizard preselect the
// activity without connection.
class PreferredActivityPrefs {
  static String key(int userId) => 'preferred_activity_$userId';

  // Saves the activity id, or forgets it when the back says the user has none
  Future<void> save(int userId, int? activityId) async {
    final prefs = await SharedPreferences.getInstance();
    if (activityId == null) {
      await prefs.remove(key(userId));
    } else {
      await prefs.setInt(key(userId), activityId);
    }
  }

  Future<int?> get(int userId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key(userId));
  }
}
