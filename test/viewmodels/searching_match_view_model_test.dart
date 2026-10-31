import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/searching_match_view_model.dart';

class _OnlineConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();

  // Simulates the phone losing the connection for a moment
  void emit(bool online) => _controller.add(online);

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  @override
  Future<bool> checkNow() async => true;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}

class _CountingGapService extends GapService {
  int calls = 0;

  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async {
    calls++;
    return [];
  }
}

// The first call waits until the test finishes it; the next ones answer with no gaps at once
class _SlowFirstGapService extends GapService {
  final first = Completer<List<Gap>>();
  int calls = 0;

  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) {
    calls++;
    return calls == 1 ? first.future : Future.value([]);
  }
}

// A gap that is happening right now
class _CurrentGapService extends GapService {
  final Gap gap;
  _CurrentGapService(this.gap);

  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async => [gap];
}

// No candidates; the user's matches come from GET /matches/user/{userId}
class _UserMatchesService extends MatchService {
  final List<Match> matches;
  final List<int> requestedUsers = [];
  _UserMatchesService(this.matches);

  @override
  Future<List<MatchCandidate>> getCandidates(int gapId,
          {bool useSameCareer = false, bool useSharedInterests = false, bool useEffort = false}) async =>
      [];

  @override
  Future<List<Match>> getByUser(int userId) async {
    requestedUsers.add(userId);
    return matches;
  }
}

void main() {
  test('the search sends its first request immediately, without an artificial wait', () async {
    final gapService = _CountingGapService();
    final vm = SearchingMatchViewModel(
      1,
      MatchModeEnum.career,
      gapService: gapService,
      connectivity: _OnlineConnectivity(),
    );

    final search = vm.search();
    // One turn of the event loop is enough for the first request to go out
    await Future<void>.delayed(Duration.zero);

    expect(gapService.calls, 1);
    await search;
    vm.dispose();
  });

  test('J-5: an old search that fails after Reintentar does not cancel the new search', () async {
    final gapService = _SlowFirstGapService();
    final connectivity = _OnlineConnectivity();
    final vm = SearchingMatchViewModel(1, MatchModeEnum.career, gapService: gapService, connectivity: connectivity);

    final oldSearch = vm.search();
    // The connection drops and comes back, the user taps Reintentar and a new search starts
    connectivity.emit(false);
    await Future<void>.delayed(Duration.zero);
    expect(vm.connectionLost, isTrue);
    expect(await vm.retry(), isTrue);
    final newResult = await vm.search();

    // Now the first request fails late
    gapService.first.completeError(const SocketException('late failure'));
    final oldResult = await oldSearch;

    expect(newResult, isA<NoMatches>());
    expect(oldResult, isNull);
    expect(vm.connectionLost, isFalse);
    vm.dispose();
  });

  test('J-5: an old search that answers late gives no second result', () async {
    final gapService = _SlowFirstGapService();
    final connectivity = _OnlineConnectivity();
    final vm = SearchingMatchViewModel(1, MatchModeEnum.career, gapService: gapService, connectivity: connectivity);

    final oldSearch = vm.search();
    connectivity.emit(false);
    await Future<void>.delayed(Duration.zero);
    await vm.retry();
    final newResult = await vm.search();

    gapService.first.complete([]);

    expect(newResult, isA<NoMatches>());
    expect(await oldSearch, isNull);
    vm.dispose();
  });

  test('J-8: the accepted match of the gap is found among the matches of the user', () async {
    final now = DateTime.now();
    final gap = Gap(id: 5, startTime: now.subtract(const Duration(minutes: 5)), endTime: now.add(const Duration(minutes: 30)));
    final matchService = _UserMatchesService([
      Match(id: 9, startTime: gap.startTime, endTime: gap.endTime, status: MatchStatusEnum.ACCEPTED, proposerGapId: 5, acceptorGapId: 8),
    ]);
    final vm = SearchingMatchViewModel(1, MatchModeEnum.career,
        gapService: _CurrentGapService(gap), matchService: matchService, connectivity: _OnlineConnectivity());

    final result = await vm.search();

    expect(result, isA<ExistingMatch>());
    expect((result as ExistingMatch).matchId, 9);
    expect(matchService.requestedUsers, [1]);
    vm.dispose();
  });

  test('J-16: an error that is not the connection gives SearchError with a message, not NoMatches', () async {
    final vm = SearchingMatchViewModel(1, MatchModeEnum.career,
        gapService: _FailingGapService(), connectivity: _OnlineConnectivity());

    final result = await vm.search();

    expect(result, isA<SearchError>());
    expect((result as SearchError).message, 'No pudimos buscar un match. Intenta de nuevo');
    expect(vm.connectionLost, isFalse);
    vm.dispose();
  });
}

// The back answers with an error that is not a network failure
class _FailingGapService extends GapService {
  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async => throw TypeError();
}
