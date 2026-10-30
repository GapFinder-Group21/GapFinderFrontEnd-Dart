import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/services/class_block_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_generation_guard.dart';
import 'package:gapfinderfrontend_dart/services/gap_reminder_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/schedule/schedule_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'secure_storage_mock.dart';

class FakeClassBlockService extends ClassBlockService {
  @override
  Future<List<ClassBlock>> getByUser(int userId) async => [];
}

class CountingGapService extends GapService {
  int generateCalls = 0;
  bool generateFails = false;

  @override
  Future<List<Gap>> generateWeek(int userId, {DateTime? weekStart}) async {
    generateCalls++;
    if (generateFails) throw Exception('cannot generate');
    return [];
  }

  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async => [];
}

class FakeAuthService extends AuthService {
  @override
  Future<void> logout() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  late CountingGapService gaps;
  late ScheduleViewModel vm;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage.install();
    storage.setUserId(1);
    gaps = CountingGapService();
    vm = ScheduleViewModel(
      classBlockService: FakeClassBlockService(),
      gapService: gaps,
      authService: FakeAuthService(),
    );
  });

  tearDown(() {
    vm.dispose();
    storage.uninstall();
  });

  group('generate-week is not asked on every refresh', () {
    test('refreshing the schedule five times asks the back once', () async {
      await vm.init();
      for (var i = 0; i < 4; i++) {
        await vm.refresh();
      }

      expect(gaps.generateCalls, 1);
    });

    test('if the back fails, the next refresh asks again', () async {
      gaps.generateFails = true;
      await vm.init();
      expect(gaps.generateCalls, 1);

      gaps.generateFails = false;
      await vm.refresh();
      await vm.refresh();

      expect(gaps.generateCalls, 2); // the failed one and the one that worked; the last refresh did not ask
    });

    test('after the class blocks change the next refresh asks again', () async {
      await vm.init();
      await vm.refresh();
      expect(gaps.generateCalls, 1);

      await GapGenerationGuard.invalidate(1);
      await vm.refresh();

      expect(gaps.generateCalls, 2);
    });
  });

  group('GapGenerationGuard', () {
    test('it is due the first time, not later the same day, and again the next day', () async {
      final today = DateTime(2026, 10, 30, 9);

      expect(await GapGenerationGuard.isDue(5, now: today), isTrue);
      await GapGenerationGuard.markDone(5, now: today);
      expect(await GapGenerationGuard.isDue(5, now: today.add(const Duration(hours: 8))), isFalse);
      expect(await GapGenerationGuard.isDue(5, now: today.add(const Duration(days: 1))), isTrue);
    });

    test('each user has their own day', () async {
      final today = DateTime(2026, 10, 30, 9);
      await GapGenerationGuard.markDone(5, now: today);

      expect(await GapGenerationGuard.isDue(6, now: today), isTrue);
    });

    test('invalidateAll forgets every user', () async {
      final today = DateTime(2026, 10, 30, 9);
      await GapGenerationGuard.markDone(5, now: today);
      await GapGenerationGuard.markDone(6, now: today);

      await GapGenerationGuard.invalidateAll();

      expect(await GapGenerationGuard.isDue(5, now: today), isTrue);
      expect(await GapGenerationGuard.isDue(6, now: today), isTrue);
    });
  });

  group('the id of a reminder', () {
    test('comes from the start of the gap, so it does not change when the gap gets a new id', () {
      final now = DateTime(2026, 10, 30, 8, 0);
      final start = DateTime(2026, 10, 30, 10, 0);
      final end = DateTime(2026, 10, 30, 12, 0);

      final before = GapReminderService.plan([Gap(id: 11, startTime: start, endTime: end)], 5, now);
      final after = GapReminderService.plan([Gap(id: 987, startTime: start, endTime: end)], 5, now);

      expect(before.single.notificationId, after.single.notificationId);
    });

    test('is different for gaps that start at different times and always positive', () {
      final a = GapReminderService.notificationIdFor(DateTime(2026, 10, 30, 10, 0));
      final b = GapReminderService.notificationIdFor(DateTime(2026, 10, 30, 14, 0));

      expect(a, isNot(b));
      expect(a, greaterThan(0));
      expect(b, lessThan(0x40000000));
    });
  });
}
