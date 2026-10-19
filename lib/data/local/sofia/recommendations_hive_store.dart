import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/storage/hive_store.dart';
import 'package:gapfinderfrontend_dart/models/responses/recommendation_response.dart';

// A saved recommendation and the time it was saved
class SavedRecommendation {
  final RecommendationResponse response;
  final DateTime? savedAt;
  SavedRecommendation(this.response, this.savedAt);
}

// Hive box "sofia_recommendations": the last recommendation of each user, saved as JSON
class RecommendationsHiveStore {
  static const boxName = 'sofia_recommendations';

  static String keyFor(int userId) => 'last_$userId';

  Future<void> save(int userId, RecommendationResponse response) async {
    final box = await HiveStore.box(boxName);
    await box.put(
      keyFor(userId),
      jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'data': response.toJson(),
      }),
    );
  }

  // The last saved recommendation, or null if there is none
  Future<SavedRecommendation?> load(int userId) async {
    final box = await HiveStore.box(boxName);
    final raw = box.get(keyFor(userId));
    if (raw is! String) return null;

    final map = jsonDecode(raw) as Map<String, dynamic>;
    return SavedRecommendation(
      RecommendationResponse.fromJson(map['data'] as Map<String, dynamic>),
      DateTime.tryParse(map['savedAt'] as String? ?? ''),
    );
  }
}
