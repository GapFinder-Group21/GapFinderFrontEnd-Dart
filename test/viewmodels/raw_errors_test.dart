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
import 'package:gapfinderfrontend_dart/services/google_service.dart';
import 'package:gapfinderfrontend_dart/services/interest_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/google_calendar_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/interests_view_model.dart';

import 'secure_storage_mock.dart';

class _InterestService extends InterestService {
  Object? error;

  @override
  Future<List<Interest>> getInterests() async {
    if (error != null) throw error!;
    return [Interest(id: 1, name: 'Chess')];
  }
}

class _UserService extends UserService {
  Object? error;

  @override
  Future<void> addInterest(int userId, int interestId) async {
    if (error != null) throw error!;
  }
}

class _GoogleService extends GoogleService {
  Object? error;

  @override
  Future<bool> importSchedule() async => throw error!;
}

// Keeps what the Google import saves in its file
class _Cache extends MiguelLocalCache {
  _Cache({super.interestsCatalog, super.userInterests});

  String? savedImportMessage;

  @override
  void saveGoogleImport({required bool success, required String message}) => savedImportMessage = message;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final storage = SecureStorageMock();
  late Database db;
  late _Cache cache;
  late OutboxService outbox;
  late _InterestService interests;
  late _UserService users;

  setUp(() async {
    storage.install();
    storage.setUserId(1);
    SharedPreferences.setMockInitialValues({});
    InterestsViewModel.clearCache();
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    cache = _Cache(
      interestsCatalog: InterestsCatalogDao(database: () async => db),
      userInterests: UserInterestsDao(database: () async => db),
    );
    outbox = OutboxService.forTesting(database: () async => db, send: (m, e, b) async => http.Response('', 200));
    interests = _InterestService();
    users = _UserService();
  });

  tearDown(() async {
    storage.uninstall();
    await outbox.dispose();
    await db.close();
  });

  InterestsViewModel openScreen() =>
      InterestsViewModel(interestService: interests, userService: users, localCache: cache, outbox: outbox);

  bool looksRaw(String text) =>
      text.contains('Exception') || text.contains('TypeError') || text.contains('Instance of') || text.contains('Error:');

  group('interests: no raw exception reaches the user', () {
    test('a failure that is not ours when saving shows a Spanish message', () async {
      users.error = const FormatException('Unexpected character (at character 1)');
      final vm = openScreen();
      await vm.init();

      vm.toggleInterest(1);
      expect(await vm.save(), isFalse);

      expect(vm.errorMessage, InterestsViewModel.saveNetworkMessage);
      expect(looksRaw(vm.errorMessage!), isFalse);
      vm.dispose();
    });

    test('a refusal text of the back that looks technical is replaced by the Spanish message', () async {
      users.error = Exception('Exception: java.lang.NullPointerException at com.gapfinder.Foo');
      final vm = openScreen();
      await vm.init();

      vm.toggleInterest(1);
      await vm.save();

      expect(vm.errorMessage, InterestsViewModel.saveNetworkMessage);
      vm.dispose();
    });

    test('a readable text of the back is shown without "Exception:"', () async {
      users.error = Exception('El interés ya no existe');
      final vm = openScreen();
      await vm.init();

      vm.toggleInterest(1);
      await vm.save();

      expect(vm.errorMessage, 'El interés ya no existe');
      vm.dispose();
    });

    test('a failure that is not ours when loading the catalog shows a Spanish message', () async {
      interests.error = const FormatException('Unexpected character');
      final vm = openScreen();

      await vm.init();

      expect(vm.loadError, InterestsViewModel.loadNetworkMessage);
      expect(looksRaw(vm.loadError!), isFalse);
      vm.dispose();
    });
  });

  group('google import: no raw exception on screen or in the saved file', () {
    test('an error that is not ours shows the Spanish message and saves only that', () async {
      final google = _GoogleService()..error = const FormatException('Unexpected character');
      final vm = GoogleCalendarViewModel(googleService: google, localCache: cache);

      await vm.importSchedule();

      expect(vm.phase, GoogleImportPhase.error);
      expect(vm.errorMessage, GoogleCalendarViewModel.failedMessage);
      expect(cache.savedImportMessage, GoogleCalendarViewModel.failedMessage);
      vm.dispose();
    });

    test('the text of our own exception is shown without "Exception:"', () async {
      final google = _GoogleService()..error = Exception('Error al importar el horario: 500');
      final vm = GoogleCalendarViewModel(googleService: google, localCache: cache);

      await vm.importSchedule();

      expect(vm.errorMessage, 'Error al importar el horario: 500');
      expect(cache.savedImportMessage, isNot(contains('Exception')));
      vm.dispose();
    });
  });
}
