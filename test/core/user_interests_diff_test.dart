import 'dart:convert';
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

import '../viewmodels/secure_storage_mock.dart';

class _FakeInterestService extends InterestService {
  @override
  Future<List<Interest>> getInterests() async => [Interest(id: 1, name: 'Chess'), Interest(id: 2, name: 'Music')];
}

// Records what the back receives
class _FakeUserService extends UserService {
  final added = <int>[];
  final removed = <int>[];
  Object? removeError;

  @override
  Future<void> addInterest(int userId, int interestId) async => added.add(interestId);

  @override
  Future<void> removeInterest(int userId, int interestId) async {
    if (removeError != null) throw removeError!;
    removed.add(interestId);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final storage = SecureStorageMock();
  late Database db;
  late OutboxService outbox;
  late UserInterestsDao dao;
  late _FakeUserService users;

  setUp(() async {
    storage.install();
    storage.setUserId(1);
    SharedPreferences.setMockInitialValues({});
    InterestsViewModel.clearCache();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = UserInterestsDao(database: () async => db);
    outbox = OutboxService.forTesting(database: () async => db, send: (m, e, b) async => http.Response('', 200));
    users = _FakeUserService();
  });

  tearDown(() async {
    storage.uninstall();
    await outbox.dispose();
    await db.close();
  });

  Future<InterestsViewModel> openScreen() async {
    final vm = InterestsViewModel(
      interestService: _FakeInterestService(),
      userService: users,
      localCache: MiguelLocalCache(interestsCatalog: InterestsCatalogDao(database: () async => db), userInterests: dao),
      outbox: outbox,
    );
    await vm.init();
    return vm;
  }

  Future<Map<String, dynamic>> queuedBody() async {
    final rows = await db.query('outbox');
    expect(rows, hasLength(1));
    return jsonDecode(rows.single['body'] as String) as Map<String, dynamic>;
  }

  group('interests: only the difference is sent', () {
    test('unticking one interest and saving sends the DELETE and no POST', () async {
      await dao.replaceAllForUser(1, {1, 2}, {1, 2});
      final vm = await openScreen();

      vm.toggleInterest(2);
      expect(await vm.save(), isTrue);

      expect(users.removed, [2]);
      expect(users.added, isEmpty);
      vm.dispose();
    });

    test('ticking a new one sends only the POST of the new one', () async {
      await dao.replaceAllForUser(1, {1}, {1});
      final vm = await openScreen();

      vm.toggleInterest(2);
      expect(await vm.save(), isTrue);

      expect(users.added, [2]);
      expect(users.removed, isEmpty);
      vm.dispose();
    });

    test('without network the delete is queued and the handler sends it later', () async {
      await dao.replaceAllForUser(1, {1, 2}, {1, 2});
      users.removeError = http.ClientException('no network'); // the network fails while sending
      final vm = await openScreen();

      vm.toggleInterest(2);
      expect(await vm.save(), isTrue);
      await Future.delayed(const Duration(milliseconds: 100)); // SQLite is written without waiting

      final body = await queuedBody();
      expect(body['addIds'], isEmpty);
      expect(body['removeIds'], [2]);
      expect(body['interestIds'], [1]);

      final calls = <String>[];
      UserInterestsOutbox.register(
        outbox: outbox,
        dao: dao,
        post: (path) async {
          calls.add('POST $path');
          return http.Response('', 200);
        },
        delete: (path) async {
          calls.add('DELETE $path');
          return http.Response('', 204);
        },
      );
      await outbox.flush();

      expect(calls, ['DELETE /users/1/interests/2']);
      expect(await db.query('outbox'), isEmpty);
      expect((await dao.getAllForUser(1)).map((r) => r.interestId), [1]);
      vm.dispose();
    });

    test('a replaced selection keeps the deletes the first one still had to do', () async {
      await UserInterestsOutbox.enqueue(1, {1}, addIds: {}, removeIds: {2}, outbox: outbox);
      await UserInterestsOutbox.enqueue(1, {1, 3}, addIds: {3}, outbox: outbox);

      var body = await queuedBody();
      expect(body['removeIds'], [2]);
      expect(body['addIds'], [3]);

      // The user ticks it again: nothing to delete anymore
      await UserInterestsOutbox.enqueue(1, {1, 2, 3}, addIds: {2, 3}, outbox: outbox);
      body = await queuedBody();
      expect(body['removeIds'], isEmpty);
    });

    test('a row queued before the diff existed still sends every interest', () async {
      await outbox.enqueue(
        type: UserInterestsOutbox.type,
        method: 'POST',
        endpoint: '/users/1/interests',
        body: {'userId': 1, 'interestIds': [1, 2]},
        dedupeKey: UserInterestsOutbox.key(1),
        replaceIfPending: true,
      );
      final calls = <String>[];
      UserInterestsOutbox.register(
        outbox: outbox,
        dao: dao,
        post: (path) async {
          calls.add(path);
          return http.Response('', 200);
        },
        delete: (path) async => http.Response('', 204),
      );

      await outbox.flush();

      expect(calls, ['/users/1/interests/1', '/users/1/interests/2']);
    });
  });
}
