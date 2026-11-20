import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_outbox.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';

// A block of time in which the user is studying, after joining the periods that touch each other
class StudyInterval {
  final int startMillis;
  final int endMillis;

  const StudyInterval(this.startMillis, this.endMillis);

  DateTime get start => DateTime.fromMillisecondsSinceEpoch(startMillis);
  DateTime get end => DateTime.fromMillisecondsSinceEpoch(endMillis);

  @override
  bool operator ==(Object other) =>
      other is StudyInterval && other.startMillis == startMillis && other.endMillis == endMillis;

  @override
  int get hashCode => Object.hash(startMillis, endMillis);

  @override
  String toString() => 'StudyInterval($startMillis, $endMillis)';
}

// What the isolate receives: only simple data (maps of numbers), no models, because an isolate does not
// share memory with the app.
// Gap map: {id, startMillis, endMillis}. Period map: {startMillis, endMillis}.
class StudyPlanPayload {
  final List<Map<String, int>> gaps;
  final List<Map<String, int>> periods;
  final int nowMillis;

  const StudyPlanPayload({required this.gaps, required this.periods, required this.nowMillis});
}

// What the isolate returns
class StudyPlan {
  // The study time, sorted and without overlaps
  final List<StudyInterval> intervals;
  // Gaps that stay hidden: gap id -> moment (millis) until which they stay hidden
  final Map<int, int> hiddenGapUntil;
  // End of the block the user is in right now (null if they are not studying now)
  final int? activeUntilMillis;

  const StudyPlan({required this.intervals, required this.hiddenGapUntil, required this.activeUntilMillis});

  static const empty = StudyPlan(intervals: [], hiddenGapUntil: {}, activeUntilMillis: null);

  bool isHidden(int gapId) => hiddenGapUntil.containsKey(gapId);

  DateTime? hiddenUntil(int gapId) {
    final millis = hiddenGapUntil[gapId];
    return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis);
  }

  DateTime? get activeUntil =>
      activeUntilMillis == null ? null : DateTime.fromMillisecondsSinceEpoch(activeUntilMillis!);
}

// Estrategia: Multithreading (Isolate). Isolate.run runs buildStudyPlan in another isolate, so sorting and
// joining the periods and crossing them with the gaps of the week never blocks the screen.
Future<StudyPlan> buildStudyPlanInIsolate(StudyPlanPayload payload) {
  // The closure only holds the payload (simple data), so it can be sent to the other isolate
  return Isolate.run(() => buildStudyPlan(payload));
}

// Top-level function so it can run in another isolate (a closure over the ViewModel could not be sent).
// It does the same cross as the back: a gap is hidden while a period that has not ended crosses it, and it
// stays hidden until that period ends (or the gap does, if it ends first).
// 1) Sort the periods by start and join the ones that overlap or touch (one sweep).
// 2) Walk the gaps sorted by start with a pointer over the joined blocks (two pointers, no nested search).
StudyPlan buildStudyPlan(StudyPlanPayload payload) {
  debugPrint('buildStudyPlan runs in isolate: ${Isolate.current.debugName}');
  return _computePlan(payload);
}

StudyPlan _computePlan(StudyPlanPayload payload) {
  final now = payload.nowMillis;

  // A period that already ended (or is empty) hides nothing
  final periods = payload.periods
      .where((p) => p['endMillis']! > now && p['endMillis']! > p['startMillis']!)
      .toList()
    ..sort((a, b) => a['startMillis']!.compareTo(b['startMillis']!));

  final intervals = <StudyInterval>[];
  for (final p in periods) {
    final start = p['startMillis']!;
    final end = p['endMillis']!;
    if (intervals.isNotEmpty && start <= intervals.last.endMillis) {
      // Overlaps (or touches) the last block: the block grows if this period ends later
      if (end > intervals.last.endMillis) {
        intervals[intervals.length - 1] = StudyInterval(intervals.last.startMillis, end);
      }
    } else {
      intervals.add(StudyInterval(start, end));
    }
  }

  int? activeUntil;
  for (final block in intervals) {
    if (block.startMillis <= now && block.endMillis > now) {
      activeUntil = block.endMillis;
      break;
    }
  }

  final gaps = payload.gaps.where((g) => g['endMillis']! > now).toList()
    ..sort((a, b) => a['startMillis']!.compareTo(b['startMillis']!));

  final hidden = <int, int>{};
  var first = 0; // first block that can still cross the current gap (and every later one)
  for (final gap in gaps) {
    final gapStart = gap['startMillis']!;
    final gapEnd = gap['endMillis']!;

    // A block that ends before this gap starts cannot cross it nor any later gap
    while (first < intervals.length && intervals[first].endMillis <= gapStart) {
      first++;
    }

    int? until;
    for (var i = first; i < intervals.length && intervals[i].startMillis < gapEnd; i++) {
      final candidate = intervals[i].endMillis < gapEnd ? intervals[i].endMillis : gapEnd;
      if (until == null || candidate > until) until = candidate;
    }
    if (until != null) hidden[gap['id']!] = until;
  }

  return StudyPlan(intervals: intervals, hiddenGapUntil: hidden, activeUntilMillis: activeUntil);
}

// The end of the block of study time the user is in right now (null if they are not studying now).
// Small and fast, so the Match tab calls it directly instead of using the isolate.
DateTime? activeStudyUntil(List<StudyPeriod> periods, DateTime now) {
  final plan = _computePlan(StudyPlanPayload(
    gaps: const [],
    periods: [
      for (final p in periods)
        {'startMillis': p.startTime.millisecondsSinceEpoch, 'endMillis': p.endTime.millisecondsSinceEpoch},
    ],
    nowMillis: now.millisecondsSinceEpoch,
  ));
  return plan.activeUntil;
}

// What the screen shows after loading: the periods of the back plus the ones of this phone that the back
// does not have yet. Pure function, called from the ViewModels.
// - The back wins for what it knows (it gives the id and says the period was received).
// - A period saved here that the back does not have stays while it waits in the outbox (synced = false).
// - A period the user removed offline (its DELETE still waits in the outbox) is not shown again just because
//   the back still lists it: its key is pending and it is not saved here anymore.
// - A saved period the back no longer lists was removed or ended: it is dropped.
List<StudyPeriod> mergeStudyPeriods({
  required int userId,
  required List<StudyPeriod> local,
  required List<StudyPeriod> server,
  required Set<String> pendingKeys,
  required DateTime now,
}) {
  final localByClientId = {for (final p in local) p.clientId: p};
  final merged = <String, StudyPeriod>{};

  for (final period in server) {
    if (period.hasEndedAt(now)) continue;
    final removalPending = pendingKeys.contains(StudyModeOutbox.key(userId, period.clientId)) &&
        !localByClientId.containsKey(period.clientId);
    if (removalPending) continue;

    merged[period.clientId] = period.copyWith(synced: true);
  }

  for (final period in local) {
    if (period.synced || period.hasEndedAt(now)) continue;
    merged.putIfAbsent(period.clientId, () => period);
  }

  return merged.values.toList()..sort((a, b) => a.startTime.compareTo(b.startTime));
}
