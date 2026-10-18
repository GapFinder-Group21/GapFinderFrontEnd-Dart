import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_view_model.dart';

import 'secure_storage_mock.dart';

class FakeGapService extends GapService {
  List<Gap> gaps = [];
  Object? error;

  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async {
    if (error != null) throw error!;
    return gaps;
  }
}

class FakeMatchService extends MatchService {
  List<Match> matches = [];

  @override
  Future<List<Match>> getAll() async => matches;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  late FakeGapService gapService;
  late FakeMatchService matchService;
  late MatchViewModel vm;

  final now = DateTime.now();
  final currentGap = Gap(
    id: 5,
    startTime: now.subtract(const Duration(minutes: 10)),
    endTime: now.add(const Duration(minutes: 50)),
  );

  setUp(() {
    storage.install();
    storage.setUserId(1);
    gapService = FakeGapService();
    matchService = FakeMatchService();
    vm = MatchViewModel(gapService: gapService, matchService: matchService);
  });

  tearDown(() {
    vm.dispose();
    storage.uninstall();
  });

  group('MatchViewModel', () {
    test('initial state: loading, career mode and cannot match', () {
      expect(vm.isLoading, isTrue);
      expect(vm.selectedMode, MatchModeEnum.career);
      expect(vm.currentGap, isNull);
      expect(vm.canMatch, isFalse);
    });

    test('init() finds the current gap and canMatch is true', () async {
      gapService.gaps = [currentGap];

      await vm.init();

      expect(vm.isLoading, isFalse);
      expect(vm.userId, 1);
      expect(vm.currentGap?.id, 5);
      expect(vm.gapMatch, isNull);
      expect(vm.canMatch, isTrue);
    });

    test('canMatch is false when the gap already has an accepted match',
        () async {
      gapService.gaps = [currentGap];
      matchService.matches = [
        Match(
          id: 1,
          startTime: currentGap.startTime,
          endTime: currentGap.endTime,
          status: MatchStatusEnum.ACCEPTED,
          proposerGapId: 5,
          acceptorGapId: 9,
        ),
      ];

      await vm.init();

      expect(vm.gapMatch?.id, 1);
      expect(vm.canMatch, isFalse);
      expect(vm.isOngoing, isTrue);
    });

    test('no current gap when the service throws, and selectMode works',
        () async {
      gapService.error = Exception('network');

      await vm.init();
      vm.selectMode(MatchModeEnum.values.last);

      expect(vm.isLoading, isFalse);
      expect(vm.currentGap, isNull);
      expect(vm.canMatch, isFalse);
      expect(vm.selectedMode, MatchModeEnum.values.last);
    });
  });
}
