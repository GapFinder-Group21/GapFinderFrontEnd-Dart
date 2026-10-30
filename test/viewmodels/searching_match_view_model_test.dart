import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/searching_match_view_model.dart';

class _OnlineConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();

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
}
