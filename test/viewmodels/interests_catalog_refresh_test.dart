import 'dart:async';
import 'dart:io';
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

import '../viewmodels/secure_storage_mock.dart';

class _FakeInterestService extends InterestService {
  int calls = 0;
  Object? error;
  // When set, the answer waits until the test completes it
  Completer<void>? gate;
  List<Interest> answer = [Interest(id: 1, name: 'Chess'), Interest(id: 2, name: 'Music')];

  @override
  Future<List<Interest>> getInterests() async {
    calls++;
    await gate?.future;
    if (error != null) throw error!;
    return answer;
  }
}

// Keeps the future of the catalog write so the test can wait for SQLite
class _Cache extends MiguelLocalCache {
  _Cache({super.interestsCatalog, super.userInterests});

  Future<void>? catalogWrite;

  @override
  void saveInterestsCatalog(List<Interest> interests) {
    catalogWrite = interestsCatalog.replaceAll(interests);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final storage = SecureStorageMock();
  late Database db;
  late InterestsCatalogDao catalog;
  late _Cache cache;
  late OutboxService outbox;
  late _FakeInterestService service;

  setUp(() async {
    storage.install();
    storage.setUserId(1);
    SharedPreferences.setMockInitialValues({});
    InterestsViewModel.clearCache();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    catalog = InterestsCatalogDao(database: () async => db);
    cache = _Cache(interestsCatalog: catalog, userInterests: UserInterestsDao(database: () async => db));
    outbox = OutboxService.forTesting(database: () async => db, send: (m, e, b) async => http.Response('', 200));
    service = _FakeInterestService();
  });

  tearDown(() async {
    storage.uninstall();
    await outbox.dispose();
    await db.close();
  });

  InterestsViewModel openScreen() => InterestsViewModel(
        interestService: service,
        userService: UserService(),
        localCache: cache,
        outbox: outbox,
      );

  // A catalog saved before (id 7) with the given age
  Future<void> saveCatalogAged(Duration age) async {
    await catalog.replaceAll([Interest(id: 7, name: 'Chess')]);
    await db.update('interests_catalog', {'saved_at': DateTime.now().subtract(age).toIso8601String()});
  }

  group('interests catalog: saved copy first, refresh in the background', () {
    test('an old saved catalog is shown and then refreshed with what the back has now', () async {
      await saveCatalogAged(const Duration(hours: 2));
      service.gate = Completer<void>();
      final vm = openScreen();

      await vm.init();
      expect(vm.interests.map((i) => i.id), [7]); // the saved copy is what the screen showed first
      expect(vm.isLoading, isFalse);

      service.gate!.complete(); // the network answers
      await vm.refreshing;
      expect(service.calls, 1);
      expect(vm.interests.map((i) => i.id), [1, 2]); // interests added in the back appear
      expect(vm.isOffline, isFalse);
      expect(vm.lastUpdated, isNotNull);

      await cache.catalogWrite; // SQLite has the new catalog
      expect((await catalog.getAll()).map((i) => i.id), [1, 2]);
      vm.dispose();
    });

    test('the refreshed catalog goes to the memory cache: the next open is a hit with the new list', () async {
      await saveCatalogAged(const Duration(hours: 2));
      final first = openScreen();
      await first.init();
      await first.refreshing;
      first.dispose();

      await db.delete('interests_catalog'); // a hit must not read SQLite
      final second = openScreen();
      await second.init();

      expect(second.interests.map((i) => i.id), [1, 2]);
      expect(service.calls, 1);
      second.dispose();
    });

    test('a catalog saved less than an hour ago does not ask the network', () async {
      await saveCatalogAged(const Duration(minutes: 10));
      final vm = openScreen();

      await vm.init();

      expect(vm.refreshing, isNull);
      expect(service.calls, 0);
      expect(vm.interests.map((i) => i.id), [7]);
      vm.dispose();
    });

    test('if the refresh fails the saved copy stays and the screen says it is saved data', () async {
      final savedAt = DateTime.now().subtract(const Duration(hours: 2));
      await saveCatalogAged(const Duration(hours: 2));
      service.error = const SocketException('no network');
      final vm = openScreen();

      await vm.init();
      await vm.refreshing;

      expect(vm.interests.map((i) => i.id), [7]);
      expect(vm.isOffline, isTrue); // markFromCache
      expect(vm.lastUpdated!.difference(savedAt).inSeconds.abs(), lessThan(5));
      expect((await catalog.getAll()).map((i) => i.id), [7]);
      vm.dispose();
    });

    test('an empty answer in the refresh does not wipe the saved catalog', () async {
      await saveCatalogAged(const Duration(hours: 2));
      service.answer = [];
      final vm = openScreen();

      await vm.init();
      await vm.refreshing;

      expect(vm.interests.map((i) => i.id), [7]);
      expect((await catalog.getAll()).map((i) => i.id), [7]);
      vm.dispose();
    });
  });
}
