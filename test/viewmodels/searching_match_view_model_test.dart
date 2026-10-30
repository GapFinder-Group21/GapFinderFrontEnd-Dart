import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
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
}
