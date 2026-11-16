import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/models/match_history_item.dart';

// What the isolate receives: the raw answer of the back OR the items already saved (memory / SQLite),
// plus the ratings still waiting in the outbox (matchId -> rating), to show them at once.
class MatchHistoryPayload {
  final String? body;
  final List<MatchHistoryItem>? items;
  final Map<int, MatchRating> pending;

  const MatchHistoryPayload({this.body, this.items, this.pending = const {}});
}

// What the isolate returns: the list ready for the screen
class MatchHistoryResult {
  // As the back sent them (without the pending ratings): this is what is cached and saved
  final List<MatchHistoryItem> serverItems;
  // Every match, newest first, with the pending ratings already applied
  final List<MatchHistoryItem> all;
  // Completed matches I can rate now
  final List<MatchHistoryItem> toRate;
  // Matches I already rated (sent or waiting in the outbox)
  final List<MatchHistoryItem> rated;
  // Average of the stars the other students gave me (null if nobody rated me yet)
  final double? averageReceived;
  // How many I still have to rate
  final int pendingToRate;

  const MatchHistoryResult({
    required this.serverItems,
    required this.all,
    required this.toRate,
    required this.rated,
    required this.averageReceived,
    required this.pendingToRate,
  });

  static const empty = MatchHistoryResult(
    serverItems: [],
    all: [],
    toRate: [],
    rated: [],
    averageReceived: null,
    pendingToRate: 0,
  );
}

// Estrategia: Multithreading (Isolate.run). Top-level so it can run in another isolate: it parses the
// JSON of the back, sorts newest first, applies the pending ratings, groups (por calificar / calificados)
// and calculates the average received and how many are left to rate. The screen never freezes,
// even with a long history.
MatchHistoryResult processMatchHistory(MatchHistoryPayload payload) {
  debugPrint('processMatchHistory runs in isolate: ${Isolate.current.debugName}');

  final body = payload.body?.trim();
  final serverItems = body != null && body.isNotEmpty
      ? (jsonDecode(body) as List).map((j) => MatchHistoryItem.fromJson(Map<String, dynamic>.from(j as Map))).toList()
      : [...?payload.items];

  // Newest first
  serverItems.sort((a, b) => b.startTime.compareTo(a.startTime));

  // A rating waiting in the outbox shows as mine (optimistic) and the match cannot be rated again
  final all = serverItems.map((item) {
    final pending = payload.pending[item.matchId];
    if (pending == null || item.myRating != null) return item;
    return item.withMyRating(pending);
  }).toList();

  final toRate = all.where((i) => i.canRate).toList();
  final rated = all.where((i) => i.myRating != null).toList();

  final received = all.map((i) => i.otherRating?.stars).whereType<int>().toList();
  final average = received.isEmpty ? null : received.reduce((a, b) => a + b) / received.length;

  return MatchHistoryResult(
    serverItems: serverItems,
    all: all,
    toRate: toRate,
    rated: rated,
    averageReceived: average,
    pendingToRate: toRate.length,
  );
}

// Runs processMatchHistory in another isolate. Top-level so the closure only captures the payload
// (a closure over the ViewModel could not be sent).
Future<MatchHistoryResult> processMatchHistoryInIsolate(MatchHistoryPayload payload) =>
    Isolate.run(() => processMatchHistory(payload));
