import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/storage/hive_store.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/cache_json.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

// Profile of the logged user in Hive (box joel_user_profile, key profile_<userId>)
class UserProfileStore {
  static const boxName = 'joel_user_profile';

  static String _key(int userId) => 'profile_$userId';

  Future<void> save(User user) async {
    final box = await HiveStore.box(boxName);
    await box.put(_key(user.id), {
      'json': jsonEncode(userCacheJson(user)),
      'saved_at': DateTime.now().toIso8601String(),
    });
  }

  Future<User?> get(int userId) async {
    final entry = await _entry(userId);
    if (entry == null) return null;
    return User.fromJson(jsonDecode(entry['json'] as String) as Map<String, dynamic>);
  }

  Future<DateTime?> savedAt(int userId) async {
    final entry = await _entry(userId);
    return entry == null ? null : DateTime.parse(entry['saved_at'] as String);
  }

  Future<Map?> _entry(int userId) async {
    final box = await HiveStore.box(boxName);
    return box.get(_key(userId)) as Map?;
  }
}
