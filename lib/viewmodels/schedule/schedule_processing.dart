import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:gapfinderfrontend_dart/core/utils/display_formatters.dart';

// Kind of row in the day: a class or a free gap
enum ScheduleItemType { classBlock, gap }

// One row of the day: a class or a free gap
class ScheduleItem {
  final ScheduleItemType type;
  final String name;
  final String start;
  final String end;
  final int sortMinutes;

  ScheduleItem({
    required this.type,
    required this.name,
    required this.start,
    required this.end,
    required this.sortMinutes,
  });
}

// What the isolate receives: only simple data (maps of numbers and text), no models.
// Class map: {subject, dayIndex, startMinutes, endMinutes}.
// Gap map: {startMillis, endMillis}.
class SchedulePayload {
  final List<Map<String, dynamic>> classes;
  final List<Map<String, dynamic>> gaps;
  final int todayMillis;

  SchedulePayload({required this.classes, required this.gaps, required this.todayMillis});
}

// What the isolate returns: the rows of today, already filtered, mixed and sorted
class ScheduleProcessResult {
  final List<ScheduleItem> items;
  ScheduleProcessResult(this.items);
}

// Top-level function so it can run in another isolate (a closure over the ViewModel could not be sent).
// Same logic the ViewModel had: today's classes by start time + today's gaps, all sorted by time.
ScheduleProcessResult processSchedule(SchedulePayload payload) {
  debugPrint('processSchedule runs in isolate: ${Isolate.current.debugName}');

  final now = DateTime.fromMillisecondsSinceEpoch(payload.todayMillis);
  final todayIndex = now.weekday - 1;
  final items = <ScheduleItem>[];

  // Today's classes, sorted by start time
  final todayClasses = payload.classes.where((c) => c['dayIndex'] == todayIndex).toList()
    ..sort((a, b) => (a['startMinutes'] as int).compareTo(b['startMinutes'] as int));

  for (final c in todayClasses) {
    items.add(ScheduleItem(
      type: ScheduleItemType.classBlock,
      name: c['subject'] as String,
      start: DisplayFormatters.timeOfDay(_timeOf(c['startMinutes'] as int)),
      end: DisplayFormatters.timeOfDay(_timeOf(c['endMinutes'] as int)),
      sortMinutes: c['startMinutes'] as int,
    ));
  }

  // Today's gaps
  for (final g in payload.gaps) {
    final start = DateTime.fromMillisecondsSinceEpoch(g['startMillis'] as int);
    final end = DateTime.fromMillisecondsSinceEpoch(g['endMillis'] as int);
    if (start.year != now.year || start.month != now.month || start.day != now.day) continue;

    final startTime = TimeOfDay.fromDateTime(start);
    items.add(ScheduleItem(
      type: ScheduleItemType.gap,
      name: 'GAP',
      start: DisplayFormatters.timeOfDay(startTime),
      end: DisplayFormatters.timeOfDay(TimeOfDay.fromDateTime(end)),
      sortMinutes: startTime.hour * 60 + startTime.minute,
    ));
  }

  items.sort((a, b) => a.sortMinutes.compareTo(b.sortMinutes));
  return ScheduleProcessResult(items);
}

TimeOfDay _timeOf(int minutes) => TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
