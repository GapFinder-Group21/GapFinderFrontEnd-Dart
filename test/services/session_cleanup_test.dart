import 'dart:io';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite, databaseFactory;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_cache_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/models/enums/day_of_week_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/gap_generation_guard.dart';
import 'package:gapfinderfrontend_dart/services/session_cleanup.dart';

OpenTable _table(int id) => OpenTable(
      id: id,
      title: 'Mesa $id',
      description: 'desc',
      startTime: DateTime(2026, 5, 1, 10),
      endTime: DateTime(2026, 5, 1, 11),
      maxParticipants: 4,
      status: OpenTableStatusEnum.OPEN,
      creator: User(id: 1, name: 'Ana', email: 'ana@x.com', career: 'ISIS'),
    );

ClassBlock _block(int id) => ClassBlock(
      id: id,
      subject: 'Cálculo',
      location: 'ML',
      dayOfWeek: DayOfWeekEnum.MON,
      startTime: const TimeOfDay(hour: 8, minute: 0),
      endTime: const TimeOfDay(hour: 10, minute: 0),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the steps of the cleanup are independent', () {
    test('every step runs even if one fails, and the failed ones are reported', () async {
      final ran = <String>[];
      final failed = await SessionCleanup.run(1, steps: [
        SessionCleanupStep('first', () async => ran.add('first')),
        SessionCleanupStep('broken', () async => throw Exception('boom')),
        SessionCleanupStep('last', () async => ran.add('last')),
      ]);

      expect(ran, ['first', 'last']);
      expect(failed, ['broken']);
    });

    test('with everything working nothing is reported', () async {
      final failed = await SessionCleanup.run(null, steps: [SessionCleanupStep('ok', () async {})]);

      expect(failed, isEmpty);
    });
  });

  group('after the logout nothing of the first user is left', () {
    late Directory dir;

    setUpAll(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      dir = await Directory.systemTemp.createTemp('gapfinder_cleanup_test');
      await databaseFactoryFfi.setDatabasesPath(dir.path);
      Hive.init(dir.path); // the recommendation of the user is in a Hive box
    });

    tearDownAll(() async {
      await (await AppDatabase.instance.database).close();
      await Hive.close();
      if (await dir.exists()) await dir.delete(recursive: true);
    });

    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('pending actions, saved lists, class blocks, the owner of the list and the week marker are removed', () async {
      final db = await AppDatabase.instance.database;
      final cache = SofiaLocalCache.instance;

      // User 1 did things on the phone
      await db.insert('outbox', {
        'type': 'open_table_join',
        'method': 'POST',
        'endpoint': '/open-table-participants/table/5/join?userId=1',
        'dedupe_key': 'open_table_join:1:5',
        'created_at': DateTime.now().toIso8601String(),
        'attempts': 0,
      });
      await cache.openTables.replaceAll(OpenTableListType.mine, [_table(5), _table(6)]);
      await cache.saveMyTablesOwner(1);
      await cache.classBlocks.replaceAllForUser(1, [_block(1)]);
      await GapGenerationGuard.markDone(1);
      SharedPreferences.getInstance().then((p) => p.setBool('gap_reminders_enabled', true));

      expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')), 1);
      expect(await cache.myTablesOwner(), 1);

      // The user logs out (the reminders step cannot run in a test: there is no notification plugin)
      final failed = await SessionCleanup.run(1);
      expect(failed.where((name) => name != 'reminders'), isEmpty);

      // The user that logs in next finds nothing of the first one
      expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')), 0);
      expect(await cache.openTables.getAll(OpenTableListType.mine), isEmpty);
      expect(await cache.myTablesOwner(), isNull);
      expect(await cache.classBlocks.getAllForUser(1), isEmpty);
      expect(await GapGenerationGuard.isDue(1), isTrue);
      expect((await SharedPreferences.getInstance()).getBool('gap_reminders_enabled'), isNull);
    });

    test('if the session expired and the user is not known, what does not need the user is still removed', () async {
      final db = await AppDatabase.instance.database;
      final cache = SofiaLocalCache.instance;
      await cache.openTables.replaceAll(OpenTableListType.mine, [_table(9)]);
      await cache.saveMyTablesOwner(2);

      await SessionCleanup.run(null);

      expect(await cache.openTables.getAll(OpenTableListType.mine), isEmpty);
      expect(await cache.myTablesOwner(), isNull);
      expect(Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')), 0);
    });

    test('the list of my tables belongs to one user: the owner is saved apart', () async {
      final cache = SofiaLocalCache.instance;

      await cache.saveMyTablesOwner(3);

      expect(await cache.myTablesOwner(), 3);
    });
  });
}
