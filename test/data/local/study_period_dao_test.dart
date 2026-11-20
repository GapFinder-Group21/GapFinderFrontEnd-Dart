import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_period_dao.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';
import 'package:gapfinderfrontend_dart/services/session_cleanup.dart';

StudyPeriod _period(
  String clientId, {
  int userId = 1,
  int startHour = 10,
  int endHour = 11,
  int? serverId,
  int? gapId,
  bool synced = false,
}) {
  return StudyPeriod(
    clientId: clientId,
    userId: userId,
    startTime: DateTime(2026, 11, 23, startHour),
    endTime: DateTime(2026, 11, 23, endHour),
    serverId: serverId,
    gapId: gapId,
    synced: synced,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Database db;
  late StudyPeriodDao dao;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = StudyPeriodDao(database: () async => db);
  });

  tearDown(() => db.close());

  group('StudyPeriodDao (SQLite)', () {
    test('saves a period and reads it back, with its dates, gap and sync state', () async {
      await dao.upsert(_period('a', gapId: 7));

      final saved = (await dao.getForUser(1)).single;
      expect(saved.clientId, 'a');
      expect(saved.startTime, DateTime(2026, 11, 23, 10));
      expect(saved.endTime, DateTime(2026, 11, 23, 11));
      expect(saved.gapId, 7);
      expect(saved.serverId, isNull);
      expect(saved.synced, isFalse);
    });

    test('the same client id stays one row: the back confirming it updates it', () async {
      await dao.upsert(_period('a'));
      await dao.upsert(_period('a', serverId: 5, synced: true));

      final all = await dao.getForUser(1);
      expect(all, hasLength(1));
      expect(all.single.serverId, 5);
      expect(all.single.synced, isTrue);
    });

    test('markSynced keeps the id the back gave', () async {
      await dao.upsert(_period('a'));

      await dao.markSynced('a', 42);

      final saved = (await dao.find('a'))!;
      expect(saved.synced, isTrue);
      expect(saved.serverId, 42);
    });

    test('they come in order of start, and each user only sees their own', () async {
      await dao.upsert(_period('late', startHour: 15, endHour: 16));
      await dao.upsert(_period('early', startHour: 9, endHour: 10));
      await dao.upsert(_period('other', userId: 2));

      expect((await dao.getForUser(1)).map((p) => p.clientId), ['early', 'late']);
      expect((await dao.getForUser(2)).map((p) => p.clientId), ['other']);
    });

    test('replaceAllForUser swaps the periods of that user in one transaction and leaves the rest', () async {
      await dao.upsert(_period('old'));
      await dao.upsert(_period('other', userId: 2));

      await dao.replaceAllForUser(1, [_period('new1'), _period('new2', startHour: 12, endHour: 13)]);

      expect((await dao.getForUser(1)).map((p) => p.clientId), ['new1', 'new2']);
      expect(await dao.getForUser(2), hasLength(1));
    });

    test('delete removes one period; deleteEnded removes the ones that already ended', () async {
      await dao.upsert(_period('a', startHour: 8, endHour: 9));
      await dao.upsert(_period('b', startHour: 9, endHour: 10));
      await dao.upsert(_period('c', startHour: 11, endHour: 12));

      final removed = await dao.deleteEnded(1, DateTime(2026, 11, 23, 10));
      expect(removed, 2);
      expect((await dao.getForUser(1)).map((p) => p.clientId), ['c']);

      await dao.delete('c');
      expect(await dao.getForUser(1), isEmpty);
    });

    test('logout removes only the periods of that user, or all of them when the user is not known', () async {
      await dao.upsert(_period('a'));
      await dao.upsert(_period('b', userId: 2));

      await dao.deleteForUser(1);
      expect(await dao.getForUser(1), isEmpty);
      expect(await dao.getForUser(2), hasLength(1));

      await dao.deleteAll();
      expect(await dao.getForUser(2), isEmpty);
    });
  });

  group('StudyModePrefs (SharedPreferences)', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('remembers the duration of each user apart', () async {
      final prefs = StudyModePrefs();

      await prefs.set(1, StudyDuration.thirtyMinutes);
      await prefs.set(2, StudyDuration.untilGapEnds);

      expect(await prefs.get(1), StudyDuration.thirtyMinutes);
      expect(await prefs.get(2), StudyDuration.untilGapEnds);
      expect(await prefs.get(3), isNull);
      expect((await SharedPreferences.getInstance()).getInt('study_default_minutes:1'), 30);
      expect((await SharedPreferences.getInstance()).getInt('study_default_minutes:2'), 0);
    });

    test('clear forgets one user, clearAll forgets every user', () async {
      final prefs = StudyModePrefs();
      await prefs.set(1, StudyDuration.oneHour);
      await prefs.set(2, StudyDuration.oneHour);

      await prefs.clear(1);
      expect(await prefs.get(1), isNull);
      expect(await prefs.get(2), StudyDuration.oneHour);

      await prefs.clearAll();
      expect(await prefs.get(2), isNull);
    });
  });

  test('the logout has a step that removes the study mode of the user', () {
    final names = SessionCleanup.stepsFor(1).map((step) => step.name);

    expect(names, contains('study mode'));
  });

  group('StudyPeriod', () {
    test('the body of the POST is what the back reads: local time without zone or fractions', () {
      final period = StudyPeriod(
        clientId: 'a',
        userId: 1,
        startTime: DateTime(2026, 11, 23, 10, 5, 7, 123),
        endTime: DateTime(2026, 11, 23, 11),
        gapId: 4,
      );

      expect(period.toCreateBody(), {
        'startTime': '2026-11-23T10:05:07',
        'endTime': '2026-11-23T11:00:00',
        'gapId': 4,
        'clientId': 'a',
      });
    });

    test('is read from the StudyPeriodDTO of the back', () {
      final period = StudyPeriod.fromServer({
        'id': 15,
        'userId': 7,
        'startTime': '2026-11-23T10:00:00',
        'endTime': '2026-11-23T11:00:00',
        'gapId': null,
        'clientId': 'abc',
        'createdAt': '2026-11-23T09:58:12.345',
      });

      expect(period.serverId, 15);
      expect(period.userId, 7);
      expect(period.gapId, isNull);
      expect(period.synced, isTrue);
      expect(period.startTime, DateTime(2026, 11, 23, 10));
    });

    test('active means started and not ended; it crosses a range only if they share time', () {
      final period = _period('a'); // 10:00 - 11:00

      expect(period.isActiveAt(DateTime(2026, 11, 23, 10)), isTrue);
      expect(period.isActiveAt(DateTime(2026, 11, 23, 11)), isFalse);
      expect(period.isActiveAt(DateTime(2026, 11, 23, 9)), isFalse);
      expect(period.hasEndedAt(DateTime(2026, 11, 23, 11)), isTrue);
      expect(period.crosses(DateTime(2026, 11, 23, 10, 30), DateTime(2026, 11, 23, 12)), isTrue);
      expect(period.crosses(DateTime(2026, 11, 23, 11), DateTime(2026, 11, 23, 12)), isFalse);
    });
  });
}
