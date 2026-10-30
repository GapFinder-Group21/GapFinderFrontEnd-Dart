import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/waiting_view_model.dart';

import 'noop_local_cache.dart';

class _FakeConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool online = true;

  void emit(bool value) {
    online = value;
    _controller.add(value);
  }

  @override
  bool get isOnline => online;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  @override
  Future<bool> checkNow() async => online;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeMatches extends MatchService {
  MatchStatusEnum status = MatchStatusEnum.PENDING;
  int calls = 0;

  @override
  Future<Match> getById(int id) async {
    calls++;
    final now = DateTime.now();
    return Match(id: id, startTime: now, endTime: now.add(const Duration(minutes: 30)), status: status);
  }
}

void main() {
  late _FakeConnectivity connectivity;
  late _FakeMatches matches;
  late WaitingViewModel vm;

  setUp(() {
    connectivity = _FakeConnectivity();
    matches = _FakeMatches();
    vm = WaitingViewModel(
      matchId: 7,
      requesterId: 1,
      matchService: matches,
      localCache: NoopLocalCache(),
      connectivity: connectivity,
    );
    vm.init();
  });

  tearDown(() => vm.dispose());

  group('J-6: the waiting poller in the background', () {
    test('paused: a connection that comes back does not start the polling', () async {
      vm.pausePolling();
      connectivity.emit(false);
      connectivity.emit(true);
      await Future<void>.delayed(Duration.zero);

      expect(matches.calls, 0);
    });

    test('resumed: it checks the match at once', () async {
      vm.pausePolling();
      vm.resumePolling();
      await Future<void>.delayed(Duration.zero);

      expect(matches.calls, 1);
    });
  });

  group('J-7: one final answer gives one event', () {
    test('a connection lost and back after a rejection does not send a second rejection', () async {
      matches.status = MatchStatusEnum.REJECTED;
      final events = <WaitingEvent>[];
      vm.events.listen(events.add);

      vm.pausePolling();
      vm.resumePolling();
      await Future<void>.delayed(Duration.zero);
      expect(events.whereType<MatchRejected>().length, 1);

      connectivity.emit(false);
      connectivity.emit(true);
      await Future<void>.delayed(Duration.zero);

      expect(events.whereType<MatchRejected>().length, 1);
      expect(matches.calls, 1);
    });
  });
}
