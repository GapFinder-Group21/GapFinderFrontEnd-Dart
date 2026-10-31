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
import 'package:gapfinderfrontend_dart/viewmodels/auth/interests_processing.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/interests_view_model.dart';

import 'secure_storage_mock.dart';

class _InterestService extends InterestService {
  @override
  Future<List<Interest>> getInterests() async => [];
}

// Records what the back receives
class _UserService extends UserService {
  final added = <int>[];
  final removed = <int>[];

  @override
  Future<void> addInterest(int userId, int interestId) async => added.add(interestId);

  @override
  Future<void> removeInterest(int userId, int interestId) async => removed.add(interestId);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('normalizeInterestName', () {
    test('it handles ç, ã and õ', () {
      expect(normalizeInterestName('Ação'), 'acao');
      expect(normalizeInterestName('Corações'), 'coracoes');
      expect(normalizeInterestName('Açaí'), 'acai');
      expect(normalizeInterestName('Põe'), 'poe');
    });

    test('a decomposed (NFD) word, with combining marks, equals the composed one', () {
      expect(normalizeInterestName('Música'), 'musica'); // u + acute accent
      expect(normalizeInterestName('Música'), normalizeInterestName('Música'));
      expect(normalizeInterestName('Español'), 'espanol'); // n + tilde
      expect(normalizeInterestName('Açá'), 'aca'); // ç, plus a letter with a combining mark
    });

    test('the letters that already worked still work', () {
      expect(normalizeInterestName('  FÚTBOL '), 'futbol');
      expect(normalizeInterestName('Niño'), 'nino');
    });
  });

  group('processInterests duplicates', () {
    test('a decomposed name is a duplicate of the composed one', () {
      final result = processInterests([
        {'id': 1, 'name': 'Música'},
        {'id': 2, 'name': 'Música'},
      ]);

      expect(result, hasLength(1));
      expect(result.single['id'], 1);
    });

    test('the dropped ids are returned with the interest that was kept', () {
      final result = processInterests([
        {'id': 3, 'name': 'Música'},
        {'id': 2, 'name': 'MUSICA'},
        {'id': 9, 'name': 'musica'},
        {'id': 4, 'name': 'Ajedrez'},
      ]);

      final music = result.firstWhere((r) => r['id'] == 3);
      expect(music['duplicateIds'], [2, 9]);
      expect(result.firstWhere((r) => r['id'] == 4)['duplicateIds'], isEmpty);
    });
  });

  group('a saved selection with a dropped duplicate id', () {
    final storage = SecureStorageMock();
    late Database db;
    late UserInterestsDao userInterests;
    late OutboxService outbox;
    late _UserService users;

    setUp(() async {
      storage.install();
      storage.setUserId(1);
      SharedPreferences.setMockInitialValues({});
      InterestsViewModel.clearCache();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await AppDatabase.createModuleTables(db);
      userInterests = UserInterestsDao(database: () async => db);
      outbox = OutboxService.forTesting(database: () async => db, send: (m, e, b) async => http.Response('', 200));
      users = _UserService();

      // Two ids with the same name: the first one (1) is kept. The user had saved the second one (2).
      await InterestsCatalogDao(database: () async => db).replaceAll([
        Interest(id: 1, name: 'Chess'),
        Interest(id: 2, name: 'chess'),
        Interest(id: 3, name: 'Music'),
      ]);
      await userInterests.replaceAllForUser(1, {2}, {2});
    });

    tearDown(() async {
      storage.uninstall();
      await outbox.dispose();
      await db.close();
    });

    InterestsViewModel openScreen() => InterestsViewModel(
          interestService: _InterestService(),
          userService: users,
          localCache: MiguelLocalCache(
            interestsCatalog: InterestsCatalogDao(database: () async => db),
            userInterests: userInterests,
          ),
          outbox: outbox,
        );

    test('it is shown as the kept interest, not hidden', () async {
      final vm = openScreen();
      await vm.init();

      expect(vm.interests.map((i) => i.id), [1, 3]);
      expect(vm.isSelected(1), isTrue);
      expect(vm.isSelected(2), isFalse);
      vm.dispose();
    });

    test('saving sends the kept id and removes the dropped one, so nothing invisible is left in the back', () async {
      final vm = openScreen();
      await vm.init();

      expect(await vm.save(), isTrue);

      expect(users.added, [1]);
      expect(users.removed, [2]);
      vm.dispose();
    });
  });
}
