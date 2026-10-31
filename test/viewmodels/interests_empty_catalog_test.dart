import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/interests_catalog_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_dao.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';
import 'package:gapfinderfrontend_dart/services/interest_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/interests_view_model.dart';

import 'secure_storage_mock.dart';

class _InterestService extends InterestService {
  int calls = 0;
  List<Interest> answer = [];

  @override
  Future<List<Interest>> getInterests() async {
    calls++;
    return answer;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final storage = SecureStorageMock();
  late Database db;
  late InterestsCatalogDao catalog;
  late MiguelLocalCache cache;
  late OutboxService outbox;
  late _InterestService service;

  setUp(() async {
    storage.install();
    storage.setUserId(1);
    SharedPreferences.setMockInitialValues({});
    InterestsViewModel.clearCache();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    catalog = InterestsCatalogDao(database: () async => db);
    cache = MiguelLocalCache(interestsCatalog: catalog, userInterests: UserInterestsDao(database: () async => db));
    outbox = OutboxService.forTesting(database: () async => db, send: (m, e, b) async => http.Response('', 200));
    service = _InterestService();
  });

  tearDown(() async {
    storage.uninstall();
    await outbox.dispose();
    await db.close();
  });

  InterestsViewModel openScreen() =>
      InterestsViewModel(interestService: service, userService: UserService(), localCache: cache, outbox: outbox);

  group('an empty answer of the back', () {
    test('shows a message with a retry instead of an empty list the user cannot leave', () async {
      final vm = openScreen();

      await vm.init();

      expect(vm.loadError, InterestsViewModel.emptyCatalogMessage);
      expect(vm.interests, isEmpty);
      expect(vm.isLoading, isFalse);
      vm.dispose();
    });

    test('is not kept in memory: the next open asks the network again', () async {
      final first = openScreen();
      await first.init();
      first.dispose();

      final second = openScreen();
      await second.init();

      expect(service.calls, 2);
      second.dispose();
    });

    test('retry loads the catalog when the back answers with interests', () async {
      final vm = openScreen();
      await vm.init();
      expect(vm.loadError, isNotNull);

      service.answer = [Interest(id: 1, name: 'Chess'), Interest(id: 2, name: 'Music')];
      await vm.retryLoad();

      expect(vm.loadError, isNull);
      expect(vm.interests.map((i) => i.id), [1, 2]);
      vm.dispose();
    });

    test('never wipes a saved catalog', () async {
      await catalog.replaceAll([Interest(id: 7, name: 'Chess')]);

      cache.saveInterestsCatalog([]);
      await Future.delayed(const Duration(milliseconds: 100)); // it saves without waiting

      expect((await catalog.getAll()).map((i) => i.id), [7]);
    });
  });
}
