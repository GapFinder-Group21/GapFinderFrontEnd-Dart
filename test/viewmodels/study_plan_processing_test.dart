import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_outbox.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_periods_cache.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_plan_processing.dart';

// A moment of the day 2026-11-23 (hour and minute) in milliseconds
int _t(int hour, [int minute = 0]) => DateTime(2026, 11, 23, hour, minute).millisecondsSinceEpoch;

Map<String, int> _period(int startHour, int endHour, {int startMinute = 0, int endMinute = 0}) =>
    {'startMillis': _t(startHour, startMinute), 'endMillis': _t(endHour, endMinute)};

Map<String, int> _gap(int id, int startHour, int endHour) =>
    {'id': id, 'startMillis': _t(startHour), 'endMillis': _t(endHour)};

StudyPlan _plan({List<Map<String, int>> gaps = const [], List<Map<String, int>> periods = const [], int? now}) {
  return buildStudyPlan(StudyPlanPayload(gaps: gaps, periods: periods, nowMillis: now ?? _t(8)));
}

StudyPeriod _studyPeriod(String clientId, DateTime start, DateTime end, {int? serverId, bool synced = false}) {
  return StudyPeriod(
    clientId: clientId,
    userId: 1,
    startTime: start,
    endTime: end,
    serverId: serverId,
    synced: synced,
  );
}

void main() {
  group('buildStudyPlan: joining the periods (sort + one sweep)', () {
    test('periods that overlap or touch become one block', () {
      final plan = _plan(periods: [
        _period(9, 10),
        _period(9, 11, startMinute: 30), // 9:30 - 11:00 overlaps the first one
        _period(11, 12), // starts exactly when the block ends: it touches, so it joins
        _period(14, 15), // far away: another block
      ]);

      expect(plan.intervals, [StudyInterval(_t(9), _t(12)), StudyInterval(_t(14), _t(15))]);
    });

    test('a period inside another one does not make the block shorter', () {
      final plan = _plan(periods: [_period(9, 12), _period(10, 11)]);

      expect(plan.intervals, [StudyInterval(_t(9), _t(12))]);
    });

    test('the periods come in any order', () {
      final plan = _plan(periods: [_period(14, 15), _period(9, 10), _period(9, 11, startMinute: 30)]);

      expect(plan.intervals, [StudyInterval(_t(9), _t(11)), StudyInterval(_t(14), _t(15))]);
    });

    test('a period that already ended, or an empty one, hides nothing', () {
      final plan = _plan(now: _t(10), periods: [
        _period(8, 9), // ended
        _period(10, 10), // empty
        {'startMillis': _t(12), 'endMillis': _t(11)}, // upside down
      ]);

      expect(plan.intervals, isEmpty);
      expect(plan.activeUntilMillis, isNull);
    });

    test('no periods and no gaps: an empty plan', () {
      final plan = _plan();

      expect(plan.intervals, isEmpty);
      expect(plan.hiddenGapUntil, isEmpty);
      expect(plan.activeUntil, isNull);
    });
  });

  group('buildStudyPlan: the block the user is in right now', () {
    test('inside a block: it ends when the block ends (the joined block, not the first period)', () {
      final plan = _plan(now: _t(10), periods: [_period(9, 11), _period(11, 12)]);

      expect(plan.activeUntilMillis, _t(12));
    });

    test('the start counts as inside, the end does not', () {
      expect(_plan(now: _t(9), periods: [_period(9, 10)]).activeUntilMillis, _t(10));
      expect(_plan(now: _t(10), periods: [_period(9, 10)]).activeUntilMillis, isNull);
    });

    test('a period that starts later is not active yet', () {
      expect(_plan(now: _t(8), periods: [_period(9, 10)]).activeUntilMillis, isNull);
    });
  });

  group('buildStudyPlan: which gaps stay hidden and until when', () {
    test('a gap crossed by a period is hidden until the period ends', () {
      final plan = _plan(gaps: [_gap(1, 10, 12)], periods: [_period(9, 10, endMinute: 30)]);

      expect(plan.hiddenGapUntil, {1: _t(10, 30)});
    });

    test('a period that lasts longer than the gap hides it only until the gap ends', () {
      final plan = _plan(gaps: [_gap(1, 10, 12)], periods: [_period(9, 15)]);

      expect(plan.hiddenGapUntil, {1: _t(12)});
    });

    test('touching is not crossing: a period that ends when the gap starts, or starts when it ends', () {
      final plan = _plan(gaps: [_gap(1, 10, 12)], periods: [_period(9, 10), _period(12, 13)]);

      expect(plan.hiddenGapUntil, isEmpty);
      expect(plan.isHidden(1), isFalse);
    });

    test('a period in the middle of the gap hides the whole gap until that period ends', () {
      // The back hides the gap while any period that has not ended crosses it
      final plan = _plan(gaps: [_gap(1, 10, 14)], periods: [_period(11, 12)]);

      expect(plan.hiddenGapUntil, {1: _t(12)});
    });

    test('several gaps and several blocks, in any order', () {
      final plan = _plan(
        gaps: [_gap(3, 14, 15), _gap(1, 8, 9), _gap(2, 10, 12)],
        periods: [_period(14, 16, startMinute: 30), _period(9, 11)],
      );

      // gap 1 (8-9): the block 9-11 starts when it ends, so no. gap 2 (10-12): until 11. gap 3 (14-15): the
      // block starts at 14:30 and ends at 16, so the gap is hidden until it ends at 15
      expect(plan.hiddenGapUntil, {2: _t(11), 3: _t(15)});
    });

    test('one long block hides every gap it crosses', () {
      final plan = _plan(
        gaps: [_gap(1, 9, 10), _gap(2, 11, 12), _gap(3, 13, 14)],
        periods: [_period(8, 12, endMinute: 30)],
      );

      expect(plan.hiddenGapUntil, {1: _t(10), 2: _t(12)});
    });

    test('a gap that already ended is ignored', () {
      final plan = _plan(now: _t(11), gaps: [_gap(1, 9, 10)], periods: [_period(9, 12)]);

      expect(plan.hiddenGapUntil, isEmpty);
    });
  });

  group('activeStudyUntil (used by the Match tab)', () {
    test('is the end of the block of now, or null', () {
      final now = DateTime(2026, 11, 23, 10);
      final periods = [
        _studyPeriod('a', DateTime(2026, 11, 23, 9), DateTime(2026, 11, 23, 11)),
        _studyPeriod('b', DateTime(2026, 11, 23, 11), DateTime(2026, 11, 23, 12)),
      ];

      expect(activeStudyUntil(periods, now), DateTime(2026, 11, 23, 12));
      expect(activeStudyUntil(periods, DateTime(2026, 11, 23, 13)), isNull);
      expect(activeStudyUntil(const [], now), isNull);
    });
  });

  group('mergeStudyPeriods: what the screen shows after loading', () {
    final now = DateTime(2026, 11, 23, 10);
    DateTime at(int h, [int m = 0]) => DateTime(2026, 11, 23, h, m);

    List<StudyPeriod> merge({
      List<StudyPeriod> local = const [],
      List<StudyPeriod> server = const [],
      Set<String> pending = const {},
    }) {
      return mergeStudyPeriods(userId: 1, local: local, server: server, pendingKeys: pending, now: now);
    }

    test('what the back has is synced and keeps its id', () {
      final merged = merge(server: [_studyPeriod('a', at(10), at(11), serverId: 7)]);

      expect(merged.single.synced, isTrue);
      expect(merged.single.serverId, 7);
    });

    test('a period only saved on this phone stays while it waits to be sent', () {
      final merged = merge(local: [_studyPeriod('a', at(10), at(11))]);

      expect(merged.single.clientId, 'a');
      expect(merged.single.synced, isFalse);
    });

    test('the back wins when it already has a period that was still waiting on the phone', () {
      final merged = merge(
        local: [_studyPeriod('a', at(10), at(11))],
        server: [_studyPeriod('a', at(10), at(11), serverId: 3)],
      );

      expect(merged, hasLength(1));
      expect(merged.single.synced, isTrue);
      expect(merged.single.serverId, 3);
    });

    test('a period removed offline (its DELETE waits in the outbox) is not shown again', () {
      final merged = merge(
        server: [_studyPeriod('a', at(10), at(11), serverId: 3)],
        pending: {StudyModeOutbox.key(1, 'a')},
      );

      expect(merged, isEmpty);
    });

    test('a period still waiting on the phone is kept even if its key is pending', () {
      final merged = merge(
        local: [_studyPeriod('a', at(10), at(11))],
        server: [_studyPeriod('a', at(10), at(11), serverId: 3)],
        pending: {StudyModeOutbox.key(1, 'a')},
      );

      expect(merged, hasLength(1));
    });

    test('a synced period the back no longer lists was removed or ended: it is dropped', () {
      final merged = merge(local: [_studyPeriod('a', at(10), at(11), serverId: 3, synced: true)]);

      expect(merged, isEmpty);
    });

    test('the ones that ended are not shown, and the rest comes sorted by start', () {
      final merged = merge(server: [
        _studyPeriod('late', at(15), at(16), serverId: 2),
        _studyPeriod('ended', at(8), at(9), serverId: 1),
        _studyPeriod('soon', at(10), at(11), serverId: 3),
      ]);

      expect(merged.map((p) => p.clientId), ['soon', 'late']);
    });
  });

  group('StudyPeriodsCache.expiryFor: the cache expires at the nearest end time', () {
    final now = DateTime(2026, 11, 23, 10);

    test('it lives until the nearest end', () {
      final life = StudyPeriodsCache.expiryFor([
        _studyPeriod('a', DateTime(2026, 11, 23, 9), DateTime(2026, 11, 23, 12)),
        _studyPeriod('b', DateTime(2026, 11, 23, 9), DateTime(2026, 11, 23, 10, 30)),
      ], now: now);

      expect(life, const Duration(minutes: 30));
    });

    test('a period that already ended does not count', () {
      final life = StudyPeriodsCache.expiryFor([
        _studyPeriod('a', DateTime(2026, 11, 23, 8), DateTime(2026, 11, 23, 9)),
        _studyPeriod('b', DateTime(2026, 11, 23, 9), DateTime(2026, 11, 23, 11)),
      ], now: now);

      expect(life, const Duration(hours: 1));
    });

    test('with no periods it lives a few minutes, so a period made somewhere else shows up', () {
      expect(StudyPeriodsCache.expiryFor(const [], now: now), StudyPeriodsCache.emptyLife);
    });
  });
}
