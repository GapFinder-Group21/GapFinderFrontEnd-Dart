import 'package:shared_preferences/shared_preferences.dart';

// Last tab opened in the main screen (SharedPreferences key main_last_tab)
class MainTabPrefs {
  static const key = 'main_last_tab';

  Future<void> save(int tabIndex) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(key, tabIndex);
  }

  Future<int?> get() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(key);
  }
}
