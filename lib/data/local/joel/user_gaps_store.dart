import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/storage/hive_store.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/cache_json.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/user_profile_store.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';

// Gaps of the user in Hive (same box as the profile, key gaps_<userId>).
// With them the Match tab can know which gap is active now even without connection.
class UserGapsStore {
  static String _key(int userId) => 'gaps_$userId';

  Future<void> save(int userId, List<Gap> gaps) async {
    final box = await HiveStore.box(UserProfileStore.boxName);
    await box.put(_key(userId), {
      'json': jsonEncode(gaps.map(gapCacheJson).toList()),
      'saved_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Gap>?> get(int userId) async {
    final entry = await _entry(userId);
    if (entry == null) return null;
    final list = jsonDecode(entry['json'] as String) as List;
    return list.map((g) => Gap.fromJson(g as Map<String, dynamic>)).toList();
  }

  Future<DateTime?> savedAt(int userId) async {
    final entry = await _entry(userId);
    return entry == null ? null : DateTime.parse(entry['saved_at'] as String);
  }

  Future<Map?> _entry(int userId) async {
    final box = await HiveStore.box(UserProfileStore.boxName);
    return box.get(_key(userId)) as Map?;
  }
}
