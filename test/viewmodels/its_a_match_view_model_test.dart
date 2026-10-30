import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/its_a_match_view_model.dart';

import 'noop_local_cache.dart';
import 'secure_storage_mock.dart';

class _FakeConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool online = false;

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

Match _match(MatchStatusEnum status) {
  final now = DateTime.now();
  return Match(id: 3, startTime: now, endTime: now.add(const Duration(minutes: 30)), status: status);
}

// SQLite answers only when the test opens the gate
class _SlowSavedCache extends NoopLocalCache {
  final gate = Completer<void>();
  final Object saved;
  _SlowSavedCache(this.saved);

  @override
  Future<T?> safeRead<T>(String what, Future<T?> Function() read) async {
    await gate.future;
    return saved as T;
  }
}

class _FakeMatches extends MatchService {
  @override
  Future<Match> getById(int id) async => _match(MatchStatusEnum.COMPLETED);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();

  setUp(() {
    storage.install();
    storage.setUserId(1);
  });

  tearDown(() => storage.uninstall());

  test('J-19: a saved copy read after the network answered does not replace the fresher match', () async {
    final cache = _SlowSavedCache((_match(MatchStatusEnum.ACCEPTED), DateTime(2026, 1, 1)));
    final connectivity = _FakeConnectivity();
    final vm = ItsAMatchViewModel(3, matchService: _FakeMatches(), localCache: cache, connectivity: connectivity);

    final init = vm.init();
    // The connection comes back while SQLite is still being read: the network answers first
    connectivity.emit(true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(vm.match?.status, MatchStatusEnum.COMPLETED);

    cache.gate.complete();
    await init;

    expect(vm.match?.status, MatchStatusEnum.COMPLETED);
    vm.dispose();
  });
}
