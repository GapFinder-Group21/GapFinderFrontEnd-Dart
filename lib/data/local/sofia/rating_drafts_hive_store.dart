import 'dart:convert';
import 'package:hive/hive.dart';
import 'package:gapfinderfrontend_dart/core/storage/hive_store.dart';

// What the user had written in the rating sheet and did not send yet
class RatingDraft {
  final int stars;
  final String comment;
  const RatingDraft({required this.stars, required this.comment});
}

// Estrategia: Local storage (Hive). Box "sofia_rating_drafts": the draft of the rating of each match
// (stars + comment), so closing the sheet or the app does not lose what the user wrote.
// Key "<userId>_<matchId>". The draft is removed when the rating reaches the back.
class RatingDraftsHiveStore {
  static const boxName = 'sofia_rating_drafts';

  final Future<Box> Function() _box;

  RatingDraftsHiveStore({Future<Box> Function()? box}) : _box = box ?? (() => HiveStore.box(boxName));

  static String keyFor(int userId, int matchId) => '${userId}_$matchId';

  Future<void> save(int userId, int matchId, RatingDraft draft) async {
    final box = await _box();
    await box.put(
      keyFor(userId, matchId),
      jsonEncode({
        'stars': draft.stars,
        'comment': draft.comment,
        'savedAt': DateTime.now().toIso8601String(),
      }),
    );
  }

  // The saved draft of the match, or null if there is none
  Future<RatingDraft?> load(int userId, int matchId) async {
    final box = await _box();
    final raw = box.get(keyFor(userId, matchId));
    if (raw is! String) return null;

    final map = jsonDecode(raw) as Map<String, dynamic>;
    return RatingDraft(
      stars: (map['stars'] as num?)?.toInt() ?? 0,
      comment: map['comment'] as String? ?? '',
    );
  }

  Future<void> delete(int userId, int matchId) async {
    final box = await _box();
    await box.delete(keyFor(userId, matchId));
  }

  // Removes every draft (logout)
  Future<void> clear() async {
    final box = await _box();
    await box.clear();
  }
}
