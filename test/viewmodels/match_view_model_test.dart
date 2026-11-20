import 'noop_local_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_period_dao.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_periods_cache.dart';

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
  final List<int> requestedUsers = [];

  @override
  Future<List<Match>> getByUser(int userId) async {
    requestedUsers.add(userId);
    return matches;
  }
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
    vm = MatchViewModel(gapService: gapService, matchService: matchService, localCache: NoopLocalCache());
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

    test('J-8: the match of the gap is looked up only among the matches of the user', () async {
      gapService.gaps = [currentGap];

      await vm.init();

      expect(matchService.requestedUsers, [1]);
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

  // Study mode: the banner and the search button read the periods the study mode screen shares
  group('MatchViewModel study mode (banner and search button)', () {
    late Database db;
    late StudyPeriodDao studyDao;
    late MatchViewModel studyVm;

    StudyPeriod period({Duration start = const Duration(minutes: -5), Duration end = const Duration(hours: 1)}) {
      return StudyPeriod(
        clientId: 'a',
        userId: 1,
        startTime: DateTime.now().add(start),
        endTime: DateTime.now().add(end),
        serverId: 3,
        synced: true,
      );
    }

    setUp(() async {
      sqfliteFfiInit();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await AppDatabase.createModuleTables(db);
      studyDao = StudyPeriodDao(database: () async => db);
      StudyPeriodsCache.clearStudyCache();
      gapService.gaps = [currentGap];
      studyVm = MatchViewModel(
        gapService: gapService,
        matchService: matchService,
        localCache: NoopLocalCache(),
        studyDao: studyDao,
      );
    });

    tearDown(() async {
      studyVm.dispose();
      await db.close();
      StudyPeriodsCache.clearStudyCache();
    });

    test('an active study period shows the banner and turns the search off', () async {
      await studyDao.upsert(period());

      await studyVm.init();
      await studyVm.loadStudy();

      expect(studyVm.currentGap?.id, 5);
      expect(studyVm.studyActiveUntil, isNotNull);
      expect(studyVm.isStudying, isTrue);
      expect(studyVm.canMatch, isFalse);
    });

    test('without a study period the search stays on', () async {
      await studyVm.init();
      await studyVm.loadStudy();

      expect(studyVm.studyActiveUntil, isNull);
      expect(studyVm.canMatch, isTrue);
    });

    test('a period that already ended does not block the search', () async {
      await studyDao.upsert(period(start: const Duration(hours: -2), end: const Duration(hours: -1)));

      await studyVm.init();
      await studyVm.loadStudy();

      expect(studyVm.isStudying, isFalse);
      expect(studyVm.canMatch, isTrue);
    });

    test('it reads the periods from the shared cache without asking SQLite', () async {
      // SQLite is empty: if the banner shows, the periods came from memory
      StudyPeriodsCache.write(1, [period()], notify: false);

      await studyVm.init();
      await studyVm.loadStudy();

      expect(studyVm.isStudying, isTrue);
      expect(await studyDao.getForUser(1), isEmpty);
    });

    test('the study mode screen tells the tab through the shared cache', () async {
      await studyVm.init();
      expect(studyVm.canMatch, isTrue);

      StudyPeriodsCache.write(1, [period()]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(studyVm.isStudying, isTrue);
      expect(studyVm.canMatch, isFalse);

      StudyPeriodsCache.write(1, const []);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(studyVm.isStudying, isFalse);
      expect(studyVm.canMatch, isTrue);
    });

    test('when the period ends the cache expires, the periods are read again and the search is back', () async {
      StudyPeriodsCache.write(1, [period(end: const Duration(milliseconds: 400))], notify: false);
      await studyVm.init();
      await studyVm.loadStudy();
      expect(studyVm.isStudying, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 700));

      expect(StudyPeriodsCache.read(1), isNull); // the entry expired at the end time
      await studyVm.checkStudyExpiry();
      expect(studyVm.isStudying, isFalse);
      expect(studyVm.canMatch, isTrue);
    });
  });
}
