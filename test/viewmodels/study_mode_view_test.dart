import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_theme.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_period_dao.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/study_mode_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_mode_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_periods_cache.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/study_plan_processing.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';
import 'package:gapfinderfrontend_dart/views/match/study_mode_view.dart';

import 'noop_local_cache.dart';

class _FakeConnectivity implements ConnectivityService {
  final bool online;
  _FakeConnectivity(this.online);

  @override
  bool get isOnline => online;
  @override
  Stream<bool> get onStatusChange => const Stream<bool>.empty();
  @override
  Future<bool> checkNow() async => online;
  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
}

class _FakeGapService extends GapService {
  final List<Gap> gaps;
  _FakeGapService(this.gaps);

  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async => gaps;
}

class _FakeStudyService extends StudyModeService {
  final List<StudyPeriod> periods;
  _FakeStudyService(this.periods);

  @override
  Future<List<StudyPeriod>> getPeriods(int userId) async => periods;
}

// Draws the screen the way a phone does and fails on any layout error (an overflow is reported as an exception)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;

  setUp(() async {
    // The fonts of the app come from Google Fonts: in a test there is no network to download them
    GoogleFonts.config.allowRuntimeFetching = false;
    StudyPeriodsCache.clearStudyCache();
    SharedPreferences.setMockInitialValues({});
    OfflineAwareMixin.recheckConnection = () async => true;
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async => throw UnimplementedError(),
    );
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
  });

  // Errors of the fonts that are not found are not layout errors: only the others fail the test
  void Function(FlutterErrorDetails)? previousHandler;
  void ignoreFontErrors() {
    previousHandler = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      previousHandler?.call(details);
    };
    addTearDown(() => FlutterError.onError = previousHandler);
  }

  Future<StudyModeViewModel> openScreen(
    WidgetTester tester, {
    required ThemeData theme,
    required bool online,
    // Narrow like a small phone; tall, because the list only builds what is on screen
    Size size = const Size(360, 1800),
  }) async {
    final now = DateTime.now();
    final gaps = [
      Gap(id: 1, startTime: now.subtract(const Duration(minutes: 10)), endTime: now.add(const Duration(minutes: 50))),
      Gap(id: 2, startTime: now.add(const Duration(days: 1)), endTime: now.add(const Duration(days: 1, hours: 2))),
      Gap(id: 3, startTime: now.add(const Duration(days: 2)), endTime: now.add(const Duration(days: 2, hours: 1))),
    ];
    final periods = [
      // Going on now (countdown), made for the current gap
      StudyPeriod(
        clientId: 'now',
        serverId: 1,
        userId: 1,
        startTime: now.subtract(const Duration(minutes: 5)),
        endTime: now.add(const Duration(minutes: 30)),
        gapId: 1,
        synced: true,
      ),
      // Hides tomorrow's gap (made for it), still waiting to be sent
      StudyPeriod(
        clientId: 'tomorrow',
        userId: 1,
        startTime: gaps[1].startTime,
        endTime: gaps[1].endTime,
        gapId: 2,
      ),
    ];

    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final vm = StudyModeViewModel(
      service: _FakeStudyService(periods.where((p) => p.synced).toList()),
      gapService: _FakeGapService(gaps),
      dao: StudyPeriodDao(database: () async => db),
      localCache: NoopLocalCache(),
      outbox: outbox,
      connectivity: _FakeConnectivity(online),
      readUserId: () async => 1,
      plan: (payload) async => buildStudyPlan(payload),
    );
    // SQLite needs the real event loop, not the fake clock of the test
    await tester.runAsync(() async {
      final dao = StudyPeriodDao(database: () async => db);
      for (final period in periods) {
        await dao.upsert(period);
      }
      await vm.init();
    });

    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: ChangeNotifierProvider<StudyModeViewModel>.value(value: vm, child: const StudyModeView()),
    ));
    await tester.pump();
    return vm;
  }

  // Removes the screen so the countdown timer is cancelled before the test ends
  Future<void> closeScreen(WidgetTester tester, StudyModeViewModel vm) async {
    await tester.pumpWidget(const SizedBox());
    vm.dispose();
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';

    testWidgets('the screen draws with no layout errors on a small phone ($mode mode)', (tester) async {
      ignoreFontErrors();
      final vm = await openScreen(tester, theme: dark ? AppTheme.dark : AppTheme.light, online: true);

      expect(find.text('Modo estudio'), findsOneWidget);
      expect(find.text('Estoy estudiando ahora'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('1 h'), findsWidgets); // the chip, and the length of a gap of one hour
      expect(find.text('Hasta que termine el gap'), findsOneWidget);
      expect(find.text('Ocultar'), findsWidgets);
      expect(find.text('Quitar'), findsWidgets);
      // The period going on shows its countdown, the other one is still waiting to be sent
      expect(find.text('Termina en '), findsWidgets);
      expect(find.text('Pendiente de enviar'), findsOneWidget);
      expect(find.text('AHORA'), findsOneWidget);
      expect(find.text('PROGRAMADO'), findsOneWidget);

      await closeScreen(tester, vm);
    });
  }

  testWidgets('offline the screen shows the offline banner and still draws with no layout errors', (tester) async {
    ignoreFontErrors();
    final vm = await openScreen(tester, theme: AppTheme.light, online: false, size: const Size(320, 1800));

    expect(find.textContaining('Sin conexión'), findsOneWidget);
    expect(find.text('Estoy estudiando ahora'), findsOneWidget);

    await closeScreen(tester, vm);
  });

  testWidgets('the main switch off removes the periods that are going on', (tester) async {
    ignoreFontErrors();
    final vm = await openScreen(tester, theme: AppTheme.light, online: true);
    expect(vm.isStudyingNow, isTrue);

    await tester.runAsync(() => vm.stopStudying());
    await tester.pump();

    expect(vm.isStudyingNow, isFalse);
    expect(find.text('AHORA'), findsNothing);

    await closeScreen(tester, vm);
  });
}
