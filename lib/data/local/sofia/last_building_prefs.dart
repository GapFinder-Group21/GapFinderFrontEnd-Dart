import 'package:shared_preferences/shared_preferences.dart';

// SharedPreferences: the last building the user was detected in.
// The other keys of the app (gap_reminders_enabled, theme) are not touched.
class LastBuildingPrefs {
  static const nameKey = 'last_building_name';
  static const atKey = 'last_building_at';

  Future<void> save(String buildingName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(nameKey, buildingName);
    await prefs.setString(atKey, DateTime.now().toIso8601String());
  }

  // Forgets the last building (logout)
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(nameKey);
    await prefs.remove(atKey);
  }

  // The name of the last building, or null if there is none
  Future<String?> loadName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(nameKey);
  }

  // When that building was detected, or null if there is none
  Future<DateTime?> loadAt() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(atKey);
    return value == null ? null : DateTime.tryParse(value);
  }
}
