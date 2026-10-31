import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/interests_catalog_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_outbox.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';
import 'package:gapfinderfrontend_dart/services/interest_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/interests_view_model.dart';

import 'secure_storage_mock.dart';

class _InterestService extends InterestService {
  @override
  Future<List<Interest>> getInterests() async => [Interest(id: 1, name: 'Chess'), Interest(id: 2, name: 'Music')];
}

class _UserService extends UserService {
  Object? error;

  @override
  Future<void> addInterest(int userId, int interestId) async {
    if (error != null) throw error!;
  }
}

// Writes the rows as the real cache does and notes how many rows the outbox had at that moment
class _Cache extends MiguelLocalCache {
  _Cache(this.db, {super.interestsCatalog, super.userInterests});

  final Database db;
  final outboxRowsWhenWritten = <int>[];

  @override
  Future<void> saveUserInterests(int userId, Set<int> interestIds, Set<int> syncedIds) async {
    outboxRowsWhenWritten.add((await db.query('outbox')).length);
    await super.saveUserInterests(userId, interestIds, syncedIds);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final storage = SecureStorageMock();
  late Database db;
  late UserInterestsDao dao;
  late _Cache cache;
  late OutboxService outbox;
  late _UserService users;

  setUp(() async {
    storage.install();
    storage.setUserId(1);
    SharedPreferences.setMockInitialValues({});
    InterestsViewModel.clearCache();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = UserInterestsDao(database: () async => db);
    cache = _Cache(db, interestsCatalog: InterestsCatalogDao(database: () async => db), userInterests: dao);
    outbox = OutboxService.forTesting(database: () async => db, send: (m, e, b) async => http.Response('', 200));
    users = _UserService();
  });

  tearDown(() async {
    storage.uninstall();
    await outbox.dispose();
    await db.close();
  });

  Future<InterestsViewModel> openScreen() async {
    final vm = InterestsViewModel(
      interestService: _InterestService(),
      userService: users,
      localCache: cache,
      outbox: outbox,
    );
    await vm.init();
    return vm;
  }

  group('interests save: SQLite is written before the selection is queued', () {
    test('the rows exist, with synced = 0, when save() returns and the outbox was still empty when they were written',
        () async {
      users.error = http.ClientException('no network');
      final vm = await openScreen();

      vm.toggleInterest(1);
      vm.toggleInterest(2);
      expect(await vm.save(), isTrue);

      expect(cache.outboxRowsWhenWritten, [0]); // written first, and only once
      final rows = await dao.getAllForUser(1);
      expect(rows.map((r) => r.interestId), [1, 2]);
      expect(rows.every((r) => !r.synced), isTrue);
      vm.dispose();
    });

    test('after the outbox sends it the rows stay synced: no late write puts synced = 0 back', () async {
      users.error = http.ClientException('no network');
      final vm = await openScreen();
      vm.toggleInterest(1);
      vm.toggleInterest(2);
      expect(await vm.save(), isTrue);

      UserInterestsOutbox.register(
        outbox: outbox,
        dao: dao,
        post: (path) async => http.Response('', 200),
        delete: (path) async => http.Response('', 204),
      );
      await outbox.flush();
      await Future.delayed(const Duration(milliseconds: 100)); // time for any write that was not waited for

      final rows = await dao.getAllForUser(1);
      expect(rows.map((r) => r.interestId), [1, 2]);
      expect(rows.every((r) => r.synced), isTrue);
      vm.dispose();
    });

    test('online: the rows are synced when save() returns', () async {
      final vm = await openScreen();
      vm.toggleInterest(1);

      expect(await vm.save(), isTrue);

      final rows = await dao.getAllForUser(1);
      expect(rows.map((r) => r.interestId), [1]);
      expect(rows.single.synced, isTrue);
      vm.dispose();
    });
  });
}
