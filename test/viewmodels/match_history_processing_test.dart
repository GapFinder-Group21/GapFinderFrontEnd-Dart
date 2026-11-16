import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/match_history_item.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_history_processing.dart';

Map<String, dynamic> _json(int id, {String status = 'COMPLETED', bool canRate = false, int? my, int? other, int day = 10}) {
  final d = day.toString().padLeft(2, '0');
  return {
    'matchId': id,
    'status': status,
    'startTime': '2026-11-${d}T10:00:00',
    'endTime': '2026-11-${d}T11:00:00',
    'score': 0.7,
    'otherUser': {'id': 100 + id, 'name': 'User $id', 'email': '', 'career': 'Sistemas'},
    'myRating': my == null ? null : {'stars': my, 'comment': null, 'createdAt': '2026-11-${d}T12:00:00'},
    'otherRating': other == null ? null : {'stars': other, 'comment': 'Bien'},
    'canRate': canRate,
  };
}

void main() {
  test('parses the answer, sorts it newest first and groups it', () {
    final body = jsonEncode([
      _json(1, day: 3, my: 5, other: 4),
      _json(2, day: 9, canRate: true),
      _json(3, day: 6, status: 'ACCEPTED'),
      _json(4, day: 1, my: 3, other: 2),
    ]);

    final result = processMatchHistory(MatchHistoryPayload(body: body));

    expect(result.all.map((i) => i.matchId), [2, 3, 1, 4]);
    expect(result.toRate.map((i) => i.matchId), [2]);
    expect(result.rated.map((i) => i.matchId), [1, 4]);
    expect(result.averageReceived, 3.0);
    expect(result.pendingToRate, 1);
  });

  test('a rating waiting in the outbox shows as mine and the match leaves "por calificar"', () {
    final body = jsonEncode([_json(2, canRate: true), _json(5, canRate: true, day: 11)]);

    final result = processMatchHistory(MatchHistoryPayload(
      body: body,
      pending: {2: const MatchRating(stars: 4, comment: 'Chévere')},
    ));

    final rated = result.all.firstWhere((i) => i.matchId == 2);
    expect(rated.myRating?.stars, 4);
    expect(rated.canRate, isFalse);
    expect(result.toRate.map((i) => i.matchId), [5]);
    expect(result.pendingToRate, 1);
    // What is cached and saved is what the back said, without the optimistic rating
    expect(result.serverItems.firstWhere((i) => i.matchId == 2).myRating, isNull);
  });

  test('saved items (memory / SQLite) are processed the same way; nobody rated me = no average', () {
    final items = [_json(1, day: 2, canRate: true), _json(2, day: 8, canRate: true)]
        .map(MatchHistoryItem.fromJson)
        .toList();

    final result = processMatchHistory(MatchHistoryPayload(items: items));

    expect(result.all.map((i) => i.matchId), [2, 1]);
    expect(result.averageReceived, isNull);
    expect(result.pendingToRate, 2);
  });

  test('it also runs in another isolate with Isolate.run', () async {
    final result = await processMatchHistoryInIsolate(
      MatchHistoryPayload(body: jsonEncode([_json(1, my: 5, other: 5)])),
    );
    expect(result.averageReceived, 5.0);
  });
}
