import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/cache/expiry_policy.dart';
import 'package:gapfinderfrontend_dart/core/cache/lru_cache.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';

// Estrategia: Caching. The study periods in memory, shared by the study mode screen and the Match tab:
// when the user turns the mode on in one, the other already knows, without asking SQLite or the back again.
// LRU with one entry per user (key = user id) and the list of periods that have not ended.
// ValueBasedExpiry: the entry expires at the nearest end time of its periods, so the day the mode ends the
// next read is a miss, the periods are read again and the screens are told (the countdown on screen is
// only UI). With no periods the entry lives a few minutes, so a period made somewhere else shows up.
class StudyPeriodsCache {
  static const emptyLife = Duration(minutes: 5);

  static final LruCache<int, List<StudyPeriod>> _cache = LruCache<int, List<StudyPeriod>>(
    maxEntries: 4,
    name: 'modo estudio',
    expiryPolicy: ValueBasedExpiry<int, List<StudyPeriod>>((_, periods) => expiryFor(periods)),
  );

  // Told the user id every time the periods of a user change, so every screen updates by itself
  static final StreamController<int> _changes = StreamController<int>.broadcast();
  static Stream<int> get changes => _changes.stream;

  // How long a list of periods is trusted: until the nearest end, or a few minutes if there is none
  @visibleForTesting
  static Duration expiryFor(List<StudyPeriod> periods, {DateTime? now}) {
    final moment = now ?? DateTime.now();
    DateTime? nearest;
    for (final period in periods) {
      if (!period.endTime.isAfter(moment)) continue;
      if (nearest == null || period.endTime.isBefore(nearest)) nearest = period.endTime;
    }
    return nearest == null ? emptyLife : nearest.difference(moment);
  }

  // The periods in memory, or null if there is none or the nearest one ended (a miss)
  static List<StudyPeriod>? read(int userId) {
    final cached = _cache.get(userId);
    debugPrint('${cached == null ? 'FALLO' : 'ACIERTO'} modo estudio ${_cache.describe()}');
    return cached;
  }

  // Saves the periods of the user. notify tells the other screens (false when the caller is the only one
  // that cares, for example the Match tab reloading its own copy).
  static void write(int userId, List<StudyPeriod> periods, {bool notify = true}) {
    _cache.put(userId, List.unmodifiable(periods));
    if (notify && !_changes.isClosed) _changes.add(userId);
  }

  // Empties the periods in memory (logout and tests)
  static void clearStudyCache() => _cache.clear();
}
