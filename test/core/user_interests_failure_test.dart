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

class _FakeUserService extends UserService {
  Object? addError;

  @override
  Future<void> addInterest(int userId, int interestId) async {
    if (addError != null) throw addError!;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final storage = SecureStorageMock();
  late Database db;
  late OutboxService outbox;
  late UserInterestsDao dao;
  late List<String> posts;
  late int backStatus;

  setUp(() async {
    storage.install();
    storage.setUserId(1);
    SharedPreferences.setMockInitialValues({});
    InterestsViewModel.clearCache();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = UserInterestsDao(database: () async => db);
    outbox = OutboxService.forTesting(database: () async => db, send: (m, e, b) async => http.Response('', 200));
    posts = [];
    backStatus = 404;

    UserInterestsOutbox.register(
      outbox: outbox,
      dao: dao,
      post: (path) async {
        posts.add(path);
        return http.Response('', backStatus);
      },
      delete: (path) async => http.Response('', 204),
    );
  });

  tearDown(() async {
    storage.uninstall();
    await outbox.dispose();
    await db.close();
  });

  Future<int> rowCount() async => (await db.query('outbox')).length;

  group('user interests outbox failures', () {
    test('a final 4xx drops the row at once, records the failure and keeps synced = 0', () async {
      await dao.replaceAllForUser(1, {1}, {});
      await UserInterestsOutbox.enqueue(1, {1}, outbox: outbox);

      await outbox.flush();

      expect(posts, hasLength(1)); // not 5 attempts
      expect(await rowCount(), 0);
      final refusal = await outbox.lastRefusalFor(UserInterestsOutbox.key(1));
      expect(refusal?.message, UserInterestsOutbox.saveFailedMessage);
      expect((await dao.getAllForUser(1)).single.synced, isFalse);
    });

    test('a server error is retried and, after all the attempts, the key is exhausted', () async {
      backStatus = 500;
      await UserInterestsOutbox.enqueue(1, {1}, outbox: outbox);

      for (var i = 0; i < OutboxService.maxAttempts; i++) {
        await outbox.flush();
      }

      expect(posts, hasLength(OutboxService.maxAttempts));
      expect(await outbox.isExhausted(UserInterestsOutbox.key(1)), isTrue);
      expect(await outbox.isPending(UserInterestsOutbox.key(1)), isFalse);
    });

    test('the screen shows the failure, not "Continue", and lets the user try again', () async {
      final users = _FakeUserService()..addError = http.ClientException('no network');
      final vm = InterestsViewModel(
        interestService: _FakeInterestService(),
        userService: users,
        localCache: MiguelLocalCache(interestsCatalog: InterestsCatalogDao(database: () async => db), userInterests: dao),
        outbox: outbox,
      );
      await vm.init();

      vm.toggleInterest(1);
      expect(await vm.save(), isTrue); // queued
      expect(vm.isSavePending, isTrue);
      expect(vm.saveFailure, isNull);

      await outbox.flush(); // the back answers 404
      for (var i = 0; i < 200 && vm.saveFailure == null; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
      }

      expect(vm.saveFailure, UserInterestsOutbox.saveFailedMessage);
      expect(vm.isSavePending, isFalse);

      users.addError = null; // the network is back: the user taps again
      expect(await vm.save(), isTrue);
      expect(vm.saveFailure, isNull);
      vm.dispose();
    });
  });
}
