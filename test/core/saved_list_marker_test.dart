import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_cache_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    dir = await Directory.systemTemp.createTemp('gapfinder_marker_test');
    await databaseFactoryFfi.setDatabasesPath(dir.path);
    Hive.init(dir.path);
  });

  tearDownAll(() async {
    await (await AppDatabase.instance.database).close();
    await Hive.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('S-16: a list saved with no rows is told apart from a list never saved', () async {
    final cache = SofiaLocalCache.instance;

    expect(await cache.savedAt(OpenTableListType.mine, 5), isNull);

    await cache.saveOpenTables(OpenTableListType.mine, [], userId: 5);

    expect(await cache.openTables.getAll(OpenTableListType.mine), isEmpty);
    expect(await cache.savedAt(OpenTableListType.mine, 5), isNotNull);
    // The marker belongs to the user
    expect(await cache.savedAt(OpenTableListType.mine, 6), isNull);
  });

  test('S-16: the markers are removed on logout', () async {
    final cache = SofiaLocalCache.instance;
    await cache.markSaved(SofiaLocalCache.scheduleList, 5);

    await cache.clearUserData(5);

    expect(await cache.savedAt(SofiaLocalCache.scheduleList, 5), isNull);
  });

  test('S-17: leaving a table removes it from the saved "My open tables"', () async {
    final cache = SofiaLocalCache.instance;
    await cache.saveOpenTables(OpenTableListType.mine, [_table(1), _table(2)], userId: 5);

    await cache.removeFromMyTables(2);

    final left = await cache.openTables.getAll(OpenTableListType.mine);
    expect(left.map((t) => t.id), [1]);
  });
}
