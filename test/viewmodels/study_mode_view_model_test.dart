import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_outbox.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_period_dao.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/study_mode_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_mode_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_periods_cache.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_plan_processing.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

import 'noop_local_cache.dart';

class _FakeConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool online;
  _FakeConnectivity(this.online);

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

// Fake back: the gaps of the week
class _FakeGapService extends GapService {
  List<Gap> gaps = [];
  Object? error;
  int calls = 0;

  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return gaps;
  }
}

// Fake back: the study periods
class _FakeStudyService extends StudyModeService {
  List<StudyPeriod> periods = [];
  Object? error;
  int calls = 0;

  @override
  Future<List<StudyPeriod>> getPeriods(int userId) async {
    calls++;
    final failure = error;
    if (failure != null) throw failure;
    return periods;
  }
}

http.Response _json(int code, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), code);
http.Response _text(int code, String body) => http.Response.bytes(utf8.encode(body), code);

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;
  late StudyPeriodDao dao;
  late _FakeGapService gapService;
  late _FakeStudyService studyService;
  late _FakeConnectivity connectivity;
  late List<http.Response> postAnswers; // what the back answers to the POST of the outbox, one per request
  late List<String> deletes;
  late StudyModeViewModel vm;

  final now = DateTime.now();
  // The user is in this gap right now
  final currentGap = Gap(
    id: 5,
    startTime: now.subtract(const Duration(minutes: 10)),
    endTime: now.add(const Duration(minutes: 50)),
  );
  // A gap tomorrow
  final laterGap = Gap(
    id: 6,
    startTime: now.add(const Duration(days: 1)),
    endTime: now.add(const Duration(days: 1, hours: 1)),
  );

  StudyPeriod serverPeriod(String clientId, {int serverId = 9, Duration start = Duration.zero, Duration? end, int? gapId}) {
    return StudyPeriod(
      clientId: clientId,
      serverId: serverId,
      userId: 1,
      startTime: now.add(start),
      endTime: now.add(end ?? const Duration(hours: 1)),
      gapId: gapId,
      synced: true,
    );
  }

  StudyModeViewModel build({StudyPeriodDao? withDao}) => StudyModeViewModel(
        service: studyService,
        gapService: gapService,
        dao: withDao ?? dao,
        prefs: StudyModePrefs(),
        localCache: NoopLocalCache(),
        outbox: outbox,
        connectivity: connectivity,
        readUserId: () async => 1,
        // Same function the isolate runs, called directly in the test
        plan: (payload) async => buildStudyPlan(payload),
      );

  Future<int> outboxRows() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  setUp(() async {
    StudyPeriodsCache.clearStudyCache();
    SharedPreferences.setMockInitialValues({});
    OfflineAwareMixin.recheckConnection = () async => true;
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = StudyPeriodDao(database: () async => db);
    postAnswers = [];
    deletes = [];
    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async => _text(204, ''),
    );
    StudyModeOutbox.register(
      outbox: outbox,
      dao: dao,
      post: (path, body) async => postAnswers.isEmpty ? _json(201, {'id': 42}) : postAnswers.removeAt(0),
      get: (path) async => _json(200, []),
      delete: (path) async {
        deletes.add(path);
        return _text(204, '');
      },
    );
    gapService = _FakeGapService();
    studyService = _FakeStudyService();
    connectivity = _FakeConnectivity(true);
  });

  tearDown(() async {
    vm.dispose();
    await outbox.dispose();
    await db.close();
  });

  group('loading (memory → SQLite → back)', () {
    test('Future.wait asks the gaps and the periods together, and both are saved and shown', () async {
      gapService.gaps = [currentGap, laterGap];
      studyService.periods = [serverPeriod('a')];
      vm = build();

      await vm.init();

      expect(gapService.calls, 1);
      expect(studyService.calls, 1);
      expect(vm.isLoading, isFalse);
      expect(vm.error, isNull);
      expect(vm.periods.single.clientId, 'a');
      expect(vm.gaps.map((g) => g.id), [5, 6]);
      expect(vm.todayGaps.map((g) => g.id), [5]);
      expect(vm.laterGaps.map((g) => g.id), [6]);
      // Saved on the phone for the next time without internet
      expect((await dao.getForUser(1)).single.synced, isTrue);
    });

    test('the isolate plan marks the gaps that a period crosses as hidden', () async {
      gapService.gaps = [currentGap, laterGap];
      studyService.periods = [serverPeriod('a', gapId: 5)];
      vm = build();

      await vm.init();

      expect(vm.hiddenUntil(currentGap), isNotNull);
      expect(vm.hiddenUntil(laterGap), isNull);
      expect(vm.isStudyingNow, isTrue);
      expect(vm.hasOwnPeriod(currentGap), isTrue);
    });

    test('the error handler of the Future.wait shows the error of the back', () async {
      studyService.error = Exception('Error del servidor');
      vm = build();

      await vm.init();

      expect(vm.error, 'Error del servidor');
      expect(vm.isLoading, isFalse);
    });

    test('a technical error is never shown to the user as it is', () async {
      gapService.error = StateError('boom internal');
      vm = build();

      await vm.init();

      expect(vm.error, StudyModeViewModel.loadFailedMessage);
    });

    test('without connection the saved periods stay on screen and the back is not asked', () async {
      await dao.upsert(serverPeriod('a'));
      connectivity.online = false;
      vm = build();

      await vm.init();

      expect(vm.isOffline, isTrue);
      expect(vm.periods.single.clientId, 'a');
      expect(studyService.calls, 0);
      expect(gapService.calls, 0);
      expect(vm.error, isNull);
    });

    test('when the network fails the saved data stays and it is not an error', () async {
      await dao.upsert(serverPeriod('a'));
      studyService.error = const SocketException('no network');
      vm = build();

      await vm.init();

      expect(vm.periods.single.clientId, 'a');
      expect(vm.error, isNull);
      expect(vm.isOffline, isTrue);
    });

    test('when the connection comes back, refresh brings what the back has', () async {
      connectivity.online = false;
      vm = build();
      await vm.init();
      expect(vm.periods, isEmpty);

      connectivity.online = true;
      studyService.periods = [serverPeriod('a')];
      await vm.refresh();

      expect(vm.periods.single.clientId, 'a');
      expect(vm.isOffline, isFalse);
    });

    test('opening the screen again uses the shared cache, without reading SQLite', () async {
      studyService.periods = [serverPeriod('a')];
      vm = build();
      await vm.init();
      vm.dispose();

      // A DAO on an empty database: if the period shows, it came from memory
      final emptyDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await AppDatabase.createModuleTables(emptyDb);
      connectivity.online = false;
      vm = build(withDao: StudyPeriodDao(database: () async => emptyDb));
      await vm.init();

      expect(vm.periods.single.clientId, 'a');
      await emptyDb.close();
    });
  });

  group('turning the study mode on and off', () {
    test('offline: it shows at once, is saved with synced = 0 and goes to the outbox with its key', () async {
      connectivity.online = false;
      gapService.gaps = [currentGap];
      vm = build();
      await vm.init();

      final error = await vm.startStudying();

      expect(error, isNull);
      expect(vm.isStudyingNow, isTrue);
      final period = vm.periods.single;
      expect(period.synced, isFalse);
      expect(vm.isPending(period), isTrue);
      // The 1 h chip is the default
      expect(period.endTime.difference(period.startTime), const Duration(hours: 1));

      final saved = (await dao.getForUser(1)).single;
      expect(saved.clientId, period.clientId);
      expect(saved.synced, isFalse);

      final key = StudyModeOutbox.key(1, period.clientId);
      expect(await outbox.isPending(key), isTrue);
      final row = (await db.query('outbox')).single;
      expect(row['type'], StudyModeOutbox.addType);
      expect(row['method'], 'POST');
      expect(row['endpoint'], '/users/1/study-mode');
      final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
      expect(body['clientId'], period.clientId);
      expect(body['startTime'], isNotNull);
      expect(body['endTime'], isNotNull);

      expect(vm.takeNotice(), StudyModeViewModel.queuedNotice);
      expect(vm.takeNotice(), isNull); // it is read once
    });

    test('removing a period that never reached the back cancels the POST and deletes it: both are undone', () async {
      connectivity.online = false;
      vm = build();
      await vm.init();
      await vm.startStudying();
      final period = vm.periods.single;
      expect(await outboxRows(), 1);

      final error = await vm.removePeriod(period);

      expect(error, isNull);
      expect(vm.periods, isEmpty);
      expect(vm.isStudyingNow, isFalse);
      expect(await dao.getForUser(1), isEmpty);
      expect(await outbox.isPending(StudyModeOutbox.key(1, period.clientId)), isFalse);
      // Nothing is sent to the back: not the POST and not a DELETE
      expect(await outboxRows(), 0);
    });

    test('removing a period the back already has removes it at once and queues a DELETE', () async {
      studyService.periods = [serverPeriod('a', serverId: 5)];
      vm = build();
      await vm.init();
      connectivity.online = false;

      final error = await vm.removePeriod(vm.periods.single);

      expect(error, isNull);
      expect(vm.periods, isEmpty);
      expect(await dao.getForUser(1), isEmpty);
      final row = (await db.query('outbox')).single;
      expect(row['type'], StudyModeOutbox.removeType);
      expect(row['method'], 'DELETE');
      expect(row['endpoint'], '/users/1/study-mode/5');
      expect(row['dedupe_key'], StudyModeOutbox.key(1, 'a'));
      expect(vm.takeNotice(), StudyModeViewModel.queuedNotice);
    });

    test('a period removed offline does not come back when the back still lists it', () async {
      studyService.periods = [serverPeriod('a', serverId: 5)];
      vm = build();
      await vm.init();
      connectivity.online = false;
      await vm.removePeriod(vm.periods.single);

      // The connection is back, but the DELETE has not been sent yet and the back still has the period
      connectivity.online = true;
      await vm.refresh();

      expect(vm.periods, isEmpty);
    });

    test('when the outbox sends it, the period turns synced with the id of the back, without a notice', () async {
      connectivity.online = false;
      vm = build();
      await vm.init();
      await vm.startStudying();
      vm.takeNotice(); // the "queued" notice
      expect(vm.periods.single.synced, isFalse);

      await outbox.flush();
      await _settle();

      final period = vm.periods.single;
      expect(period.synced, isTrue);
      expect(period.serverId, 42);
      expect(vm.isPending(period), isFalse);
      expect(vm.takeNotice(), isNull);
      expect((await dao.find(period.clientId))!.synced, isTrue);
    });

    test('a refusal of the back removes the period and tells the user why', () async {
      connectivity.online = false;
      vm = build();
      await vm.init();
      await vm.startStudying();
      vm.takeNotice();
      postAnswers = [_text(422, 'Esta persona no puede activar el modo estudio')];

      await outbox.flush();
      await _settle();

      expect(vm.periods, isEmpty);
      expect(vm.isStudyingNow, isFalse);
      expect(vm.takeNotice(), 'No pudimos activar el modo estudio: Esta persona no puede activar el modo estudio');
      expect(await dao.getForUser(1), isEmpty);
    });

    test('turning it on while it is already on does nothing', () async {
      studyService.periods = [serverPeriod('a')];
      vm = build();
      await vm.init();

      final error = await vm.startStudying();

      expect(error, isNull);
      expect(vm.periods, hasLength(1));
      expect(await outboxRows(), 0);
    });

    test('the switch off removes the periods that are going on, not the ones of later', () async {
      studyService.periods = [
        serverPeriod('now', serverId: 1),
        serverPeriod('later', serverId: 2, start: const Duration(hours: 5), end: const Duration(hours: 6)),
      ];
      vm = build();
      await vm.init();

      await vm.stopStudying();

      expect(vm.periods.map((p) => p.clientId), ['later']);
      expect(vm.isStudyingNow, isFalse);
    });
  });

  group('the duration chips', () {
    test('30 min and 1 h make a period of that length starting now', () async {
      gapService.gaps = [currentGap];
      vm = build();
      await vm.init();

      await vm.selectDuration(StudyDuration.thirtyMinutes);
      await vm.startStudying();

      final period = vm.periods.single;
      expect(period.endTime.difference(period.startTime), const Duration(minutes: 30));
      expect(period.gapId, isNull);
    });

    test('"hasta que termine el gap" ends with the current gap and keeps its id', () async {
      gapService.gaps = [currentGap];
      vm = build();
      await vm.init();
      await vm.selectDuration(StudyDuration.untilGapEnds);

      await vm.startStudying();

      final period = vm.periods.single;
      expect(period.endTime, currentGap.endTime);
      expect(period.gapId, 5);
    });

    test('a very long gap is cut to the 12 hours the back accepts', () async {
      final longGap = Gap(
        id: 8,
        startTime: now.subtract(const Duration(minutes: 5)),
        endTime: now.add(const Duration(hours: 14)),
      );
      gapService.gaps = [longGap];
      vm = build();
      await vm.init();
      await vm.selectDuration(StudyDuration.untilGapEnds);

      await vm.startStudying();

      final period = vm.periods.single;
      expect(period.endTime.difference(period.startTime), StudyPeriod.maxDuration);
    });

    test('without a gap right now that chip is not available and 1 h is used', () async {
      gapService.gaps = [laterGap];
      vm = build();
      await vm.init();

      await vm.selectDuration(StudyDuration.untilGapEnds); // ignored: there is no gap to end

      expect(vm.canUseGapDuration, isFalse);
      expect(vm.selectedDuration, StudyDuration.oneHour);
      expect(await vm.startStudying(), isNull);
      final period = vm.periods.single;
      expect(period.endTime.difference(period.startTime), const Duration(hours: 1));
    });

    test('the choice is remembered for the next time (SharedPreferences, per user)', () async {
      gapService.gaps = [currentGap];
      vm = build();
      await vm.init();
      await vm.selectDuration(StudyDuration.untilGapEnds);
      vm.dispose();

      vm = build();
      await vm.init();

      expect(vm.selectedDuration, StudyDuration.untilGapEnds);
      expect((await SharedPreferences.getInstance()).getInt('study_default_minutes:1'), 0);
    });
  });

  group('hiding a gap of the week', () {
    test('"Ocultar" makes a period that covers the gap, with its id, and "mostrar" removes it', () async {
      gapService.gaps = [laterGap];
      vm = build();
      await vm.init();

      expect(await vm.hideGap(laterGap), isNull);

      final period = vm.periods.single;
      expect(period.gapId, 6);
      expect(period.startTime, laterGap.startTime);
      expect(period.endTime, laterGap.endTime);
      // The plan travels as milliseconds, so the comparison is in milliseconds
      expect(vm.hiddenUntil(laterGap)!.millisecondsSinceEpoch, laterGap.endTime.millisecondsSinceEpoch);
      expect(vm.hasOwnPeriod(laterGap), isTrue);
      // It is not "studying now": the gap is tomorrow
      expect(vm.isStudyingNow, isFalse);

      expect(await vm.showGap(laterGap), isNull);

      expect(vm.periods, isEmpty);
      expect(vm.hiddenUntil(laterGap), isNull);
    });

    test('a gap that already ended cannot be hidden', () async {
      final ended = Gap(
        id: 9,
        startTime: now.subtract(const Duration(hours: 2)),
        endTime: now.subtract(const Duration(hours: 1)),
      );
      vm = build();
      await vm.init();

      expect(await vm.hideGap(ended), StudyModeViewModel.gapEndedMessage);
      expect(vm.periods, isEmpty);
    });

    test('a gap hidden by the study mode of now cannot be shown with its own switch', () async {
      gapService.gaps = [currentGap];
      studyService.periods = [serverPeriod('a')]; // not made for that gap
      vm = build();
      await vm.init();

      expect(vm.hiddenUntil(currentGap), isNotNull);
      expect(vm.hasOwnPeriod(currentGap), isFalse);
    });
  });

  group('the periods that end', () {
    test('an ended period is not shown: the cache expires at its end time and the periods are read again', () async {
      final soon = StudyPeriod(
        clientId: 'a',
        serverId: 3,
        userId: 1,
        startTime: DateTime.now().subtract(const Duration(minutes: 1)),
        endTime: DateTime.now().add(const Duration(milliseconds: 600)),
        synced: true,
      );
      studyService.periods = [soon];
      vm = build();
      await vm.init();
      expect(vm.isStudyingNow, isTrue);
      expect(StudyPeriodsCache.read(1), isNotNull);

      await Future<void>.delayed(const Duration(milliseconds: 800));

      // The entry expired by itself at the end time: the next read is a miss
      expect(StudyPeriodsCache.read(1), isNull);
      await vm.refreshIfExpired();
      expect(vm.periods, isEmpty);
      expect(vm.isStudyingNow, isFalse);
      expect(await dao.getForUser(1), isEmpty);
    });

    test('the others are told through the shared cache when the periods change', () async {
      vm = build();
      await vm.init();
      final told = <int>[];
      final sub = StudyPeriodsCache.changes.listen(told.add);

      await vm.startStudying();
      await _settle();
      await sub.cancel();

      expect(told, contains(1));
      expect(StudyPeriodsCache.read(1)!.single.clientId, vm.periods.single.clientId);
    });
  });
}
