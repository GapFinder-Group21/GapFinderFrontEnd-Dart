import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/models/enums/day_of_week_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/services/class_block_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/schedule/schedule_view_model.dart';

import 'secure_storage_mock.dart';

class FakeClassBlockService extends ClassBlockService {
  List<ClassBlock> blocks = [];
  Object? error;

  @override
  Future<List<ClassBlock>> getByUser(int userId) async {
    if (error != null) throw error!;
    return blocks;
  }
}

class FakeGapService extends GapService {
  List<Gap> gaps = [];
  bool generateFails = false;

  @override
  Future<List<Gap>> generateWeek(int userId, {DateTime? weekStart}) async {
    if (generateFails) throw Exception('cannot generate');
    return gaps;
  }

  @override
  Future<List<Gap>> getUserGaps(int userId, {String? weekStart}) async => gaps;
}

class FakeAuthService extends AuthService {
  bool loggedOut = false;

  @override
  Future<void> logout() async => loggedOut = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  late FakeClassBlockService blocks;
  late FakeGapService gaps;
  late FakeAuthService auth;
  late ScheduleViewModel vm;

  setUp(() {
    storage.install();
    storage.setUserId(1);
    blocks = FakeClassBlockService();
    gaps = FakeGapService();
    auth = FakeAuthService();
    vm = ScheduleViewModel(
      classBlockService: blocks,
      gapService: gaps,
      authService: auth,
    );
  });

  tearDown(() {
    vm.dispose();
    storage.uninstall();
  });

  group('ScheduleViewModel', () {
    test('initial state: loading, no data and isEmpty', () {
      expect(vm.isLoading, isTrue);
      expect(vm.data, isNull);
      expect(vm.loadError, isNull);
      expect(vm.isEmpty, isTrue);
      expect(vm.todayItems, isEmpty);
    });

    test('init() loads classes and gaps, and todayItems are sorted', () async {
      final now = DateTime.now();
      final today = DayOfWeekEnum.values[now.weekday - 1];
      blocks.blocks = [
        ClassBlock(
          id: 1,
          subject: 'Calculus',
          location: 'A1',
          dayOfWeek: today,
          startTime: const TimeOfDay(hour: 23, minute: 0),
          endTime: const TimeOfDay(hour: 23, minute: 30),
        ),
      ];
      gaps.gaps = [
        Gap(
          id: 1,
          startTime: DateTime(now.year, now.month, now.day, 1, 0),
          endTime: DateTime(now.year, now.month, now.day, 2, 0),
        ),
      ];

      await vm.init();

      expect(vm.isLoading, isFalse);
      expect(vm.loadError, isNull);
      expect(vm.isEmpty, isFalse);
      expect(vm.todayItems.map((i) => i.type),
          [ScheduleItemType.gap, ScheduleItemType.classBlock]);
      expect(vm.todayItems.last.name, 'Calculus');
    });

    test('loadError is set when the service throws', () async {
      blocks.error = Exception('server down');

      await vm.refresh();

      expect(vm.isLoading, isFalse);
      expect(vm.loadError, contains('server down'));
      expect(vm.data, isNull);
    });

    test('a failing generateWeek does not break the load', () async {
      gaps.generateFails = true;

      await vm.refresh();

      expect(vm.loadError, isNull);
      expect(vm.data, isNotNull);
      expect(vm.isEmpty, isTrue);
    });

    test('loadError is set when there is no session', () async {
      storage.values.clear();

      await vm.refresh();

      expect(vm.loadError, contains('No hay usuario logueado'));
    });

    test('logout() calls the auth service', () async {
      await vm.logout();

      expect(auth.loggedOut, isTrue);
    });
  });
}
