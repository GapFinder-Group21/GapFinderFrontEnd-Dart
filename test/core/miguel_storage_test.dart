import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/google_import_store.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/interests_catalog_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/register_draft_store.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/seen_candidates_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_dao.dart';
import 'package:gapfinderfrontend_dart/models/enums/effort_type_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/responses/auth_response.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/services/google_service.dart';
import 'package:gapfinderfrontend_dart/services/interest_service.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/google_calendar_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/interests_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/register_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_found_view_model.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';

import '../viewmodels/secure_storage_mock.dart';

// Remembers what the view models ask to save, so the tests can read it
class RecordingCache extends MiguelLocalCache {
  RecordingCache({super.interestsCatalog, super.userInterests});

  final calls = <String>[];
  RegisterDraft? lastDraft;
  Set<int>? lastInterestIds;
  Set<int>? lastSyncedIds;
  int? lastCandidateMatchId;
  GoogleImportState? lastImport;

  @override
  void saveRegisterDraft(RegisterDraft draft) {
    calls.add('draft');
    lastDraft = draft;
  }

  @override
  void clearRegisterDraft() => calls.add('clearDraft');

  @override
  void advanceOnboarding(OnboardingStep step) => calls.add('step:${step.value}');

  @override
  void saveInterestsCatalog(List<Interest> interests) => calls.add('catalog:${interests.length}');

  @override
  void saveUserInterests(int userId, Set<int> interestIds, Set<int> syncedIds) {
    calls.add('userInterests');
    lastInterestIds = interestIds;
    lastSyncedIds = syncedIds;
  }

  @override
  void saveSeenCandidate(int matchId, MatchCandidate candidate) {
    calls.add('candidate');
    lastCandidateMatchId = matchId;
  }

  @override
  void saveGoogleImport({required bool success, required String message}) {
    calls.add('import:$success');
    lastImport = GoogleImportState(date: DateTime.now(), success: success, message: message);
  }
}

class FakeAuthService extends AuthService {
  Object? error;
  String? lastPassword;

  @override
  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
    required String career,
    required int semester,
    required EffortTypeEnum preferredEffort,
    required String phoneNumber,
  }) async {
    lastPassword = password;
    if (error != null) throw error!;
    return AuthResponse(id: 1, accessToken: 'a', refreshToken: 'r', email: email, name: name);
  }
}

class FakeInterestService extends InterestService {
  int calls = 0;

  @override
  Future<List<Interest>> getInterests() async {
    calls++;
    return [Interest(id: 1, name: 'Chess'), Interest(id: 2, name: 'Music')];
  }
}

class FakeUserService extends UserService {
  final Set<int> failing = {};
  Object? error;

  @override
  Future<void> addInterest(int userId, int interestId) async {
    if (error != null) throw error!;
    if (failing.contains(interestId)) throw Exception('network');
  }
}

class FakeGoogleService extends GoogleService {
  Object? error;

  @override
  Future<bool> importSchedule() async {
    if (error != null) throw error!;
    return true;
  }
}

Gap _gap(int id, int userId) => Gap(
      id: id,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      userId: userId,
      user: User(id: userId, name: 'Ana $userId', email: 'a@test.com', career: 'Systems', interests: [Interest(id: 1, name: 'Chess')]),
    );

class FakeMatchService extends MatchService {
  Object? error;

  @override
  Future<Match> sendRequest(int proposerGapId, int acceptorGapId, double score) async {
    if (error != null) throw error!;
    return Match(
      id: 42,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      status: MatchStatusEnum.PENDING,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final storage = SecureStorageMock();
  late Directory tempDir;
  late Database db;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('miguel_storage_test');
    Hive.init('${tempDir.path}/hive');

    // path_provider has no platform in tests: the "documents folder" is the temp folder
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('plugins.flutter.io/path_provider'), (call) async => tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  setUp(() async {
    storage.install();
    storage.setUserId(1);
    SharedPreferences.setMockInitialValues({});
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
  });

  tearDown(() async {
    storage.uninstall();
    await db.close();
  });

  group('SQLite', () {
    test('the catalog is replaced with a batch and read back with its saved time', () async {
      final dao = InterestsCatalogDao(database: () async => db);
      await dao.replaceAll([Interest(id: 1, name: 'Chess'), Interest(id: 2, name: 'Music')]);
      await dao.replaceAll([Interest(id: 2, name: 'Music'), Interest(id: 3, name: 'Soccer')]);

      expect((await dao.getAll()).map((i) => i.name), ['Music', 'Soccer']);
      expect(await dao.lastSavedAt(), isNotNull);
    });

    test('user_interests keeps synced = 1 only for the interests that were sent, per user', () async {
      final dao = UserInterestsDao(database: () async => db);
      await dao.replaceAllForUser(1, {1, 2, 3}, {1, 2});
      await dao.replaceAllForUser(9, {5}, {5});
      await dao.replaceAllForUser(1, {2, 3}, {2});

      final rows = await dao.getAllForUser(1);
      expect(rows.map((r) => r.interestId), [2, 3]);
      expect(rows.map((r) => r.synced), [true, false]);
      expect((await dao.getAllForUser(9)).single.synced, isTrue);
    });

    test('seen_candidates keeps both gaps with their users', () async {
      final dao = SeenCandidatesDao(database: () async => db);
      await dao.save(7, MatchCandidate(proposerGap: _gap(1, 1), acceptorGap: _gap(2, 2), score: 0.8));

      final saved = await dao.getById(7);
      expect(saved?.score, 0.8);
      expect(saved?.acceptorGap.user?.name, 'Ana 2');
      expect(saved?.acceptorGap.user?.interests.single.name, 'Chess');
      expect((await dao.getAll()).length, 1);
      expect(await dao.getById(99), isNull);
    });
  });

  group('Hive draft of the sign up', () {
    test('it saves name, email, career and semester, and never a password', () async {
      final store = RegisterDraftStore();
      await store.save(const RegisterDraft(name: 'Ana', email: 'ana@test.com', career: 'Systems', semester: '5'));

      final box = await Hive.openBox(RegisterDraftStore.boxName);
      expect(box.keys.toSet(), {'name', 'email', 'career', 'semester', 'saved_at'});
      expect(box.keys.any((k) => k.toString().toLowerCase().contains('pass')), isFalse);
      expect(box.values.any((v) => v.toString().contains('secret')), isFalse);

      final draft = await store.get();
      expect(draft?.name, 'Ana');
      expect(draft?.semester, '5');

      await store.clear();
      expect(await store.get(), isNull);
    });
  });

  group('file of the last Google import', () {
    test('it writes imports/last_google_import.json and reads it back', () async {
      final store = GoogleImportStore();
      await store.save(GoogleImportState(date: DateTime(2026, 1, 1), success: false, message: 'boom'));

      expect(File('${tempDir.path}/imports/last_google_import.json').existsSync(), isTrue);
      final state = await store.get();
      expect(state?.success, isFalse);
      expect(state?.message, 'boom');
      expect(state?.date, DateTime(2026, 1, 1));
    });
  });

  group('SharedPreferences onboarding_step', () {
    test('it only moves forward', () async {
      final prefs = OnboardingPrefs();
      await prefs.advanceTo(OnboardingStep.interests);
      await prefs.advanceTo(OnboardingStep.register); // an older screen opened again
      expect((await SharedPreferences.getInstance()).getString('onboarding_step'), 'interests');

      await prefs.advanceTo(OnboardingStep.scheduleSetup);
      expect((await SharedPreferences.getInstance()).getString('onboarding_step'), 'schedule_setup');
      expect(await prefs.get(), OnboardingStep.scheduleSetup);

      await prefs.advanceTo(OnboardingStep.done);
      expect(await prefs.get(), OnboardingStep.done);
    });
  });

  group('view models', () {
    late RecordingCache cache;
    late OutboxService outbox;

    Future<List<Map<String, Object?>>> outboxRows() => db.query('outbox');

    setUp(() {
      cache = RecordingCache(
        interestsCatalog: InterestsCatalogDao(database: () async => db),
        userInterests: UserInterestsDao(database: () async => db),
      );
      outbox = OutboxService.forTesting(
        database: () async => db,
        send: (method, endpoint, body) async => throw UnimplementedError(),
      );
    });

    tearDown(() => outbox.dispose());

    Future<bool> register(RegisterViewModel vm) => vm.register(
          name: 'Ana',
          email: 'ana@test.com',
          password: 'secret123',
          confirmPassword: 'secret123',
          semesterText: '5',
          phone: '3001234567',
        );

    test('register: the draft is saved while typing and deleted when the account is created', () async {
      final auth = FakeAuthService();
      final vm = RegisterViewModel(authService: auth, localCache: cache);

      vm.saveDraft(name: 'Ana', email: 'ana@test.com', semesterText: '5');
      expect(cache.lastDraft?.name, 'Ana');
      expect(cache.calls, ['draft', 'step:register']);

      expect(await register(vm), isTrue);
      expect(cache.calls, containsAllInOrder(['clearDraft', 'step:interests']));
      expect(auth.lastPassword, 'secret123'); // the password goes to the back, not to the storage
      vm.dispose();
    });

    test('register: if it fails the draft stays', () async {
      final auth = FakeAuthService()..error = Exception('taken');
      final vm = RegisterViewModel(authService: auth, localCache: cache);

      expect(await register(vm), isFalse);
      expect(cache.calls, isNot(contains('clearDraft')));
      vm.dispose();
    });

    test('register: a network failure shows its own message and the draft stays', () async {
      final auth = FakeAuthService()..error = const SocketException('no network');
      final vm = RegisterViewModel(authService: auth, localCache: cache);

      expect(await register(vm), isFalse);
      expect(vm.errorMessage, RegisterViewModel.offlineMessage);
      expect(cache.calls, isNot(contains('clearDraft')));
      vm.dispose();
    });

    test('interests: the catalog comes from SQLite and the network is not asked', () async {
      await InterestsCatalogDao(database: () async => db).replaceAll([Interest(id: 7, name: 'Chess')]);
      final service = FakeInterestService();
      final vm = InterestsViewModel(
          interestService: service, userService: FakeUserService(), localCache: cache, outbox: outbox);

      await vm.init();
      expect(vm.interests.map((i) => i.id), [7]);
      expect(service.calls, 0);
      vm.dispose();
    });

    test('interests: with no saved catalog it goes to the network once and saves it', () async {
      final service = FakeInterestService();
      final vm = InterestsViewModel(
          interestService: service, userService: FakeUserService(), localCache: cache, outbox: outbox);

      await vm.init();
      expect(service.calls, 1);
      expect(cache.calls, containsAllInOrder(['step:interests', 'catalog:2']));
      vm.dispose();
    });

    test('interests: saving many times without network leaves one pending action with the last selection', () async {
      final users = FakeUserService()..error = const SocketException('no network');
      final vm = InterestsViewModel(
          interestService: FakeInterestService(), userService: users, localCache: cache, outbox: outbox);
      await vm.init();

      vm.toggleInterest(1);
      expect(await vm.save(), isTrue);
      expect(vm.takeNotice(), InterestsViewModel.offlineNotice);
      expect(vm.isSavePending, isTrue);

      vm.toggleInterest(2);
      expect(vm.isSavePending, isFalse); // the selection changed, so it can be saved again
      expect(await vm.save(), isTrue);
      expect(await vm.save(), isTrue);

      final rows = await outboxRows();
      expect(rows, hasLength(1));
      expect(rows.single['dedupe_key'], 'user_interests_save:1');
      expect(rows.single['type'], 'user_interests_save');
      expect(rows.single['body'], contains('[1,2]'));
      expect(cache.lastSyncedIds, isEmpty); // synced = 0 until the back receives them
      vm.dispose();
    });

    test('interests: save marks synced only the ones that were sent', () async {
      final users = FakeUserService()..failing.add(2);
      final vm = InterestsViewModel(
          interestService: FakeInterestService(), userService: users, localCache: cache, outbox: outbox);

      await vm.init();

      vm.toggleInterest(1);
      vm.toggleInterest(2);
      expect(await vm.save(), isFalse); // the second one fails
      expect(cache.lastInterestIds, {1, 2});
      expect(cache.lastSyncedIds, {1});

      users.failing.clear();
      expect(await vm.save(), isTrue);
      expect(cache.lastSyncedIds, {1, 2});
      expect(cache.calls.last, 'userInterests');
      expect(cache.calls, contains('step:schedule_setup'));
      vm.dispose();
    });

    test('google import: it saves how it ended and finishes the onboarding on success', () async {
      final google = FakeGoogleService();
      final vm = GoogleCalendarViewModel(googleService: google, localCache: cache);

      await vm.importSchedule();
      expect(cache.lastImport?.success, isTrue);
      expect(cache.calls, containsAllInOrder(['import:true', 'step:done']));

      cache.calls.clear();
      google.error = Exception('boom');
      await vm.importSchedule();
      expect(cache.lastImport?.success, isFalse);
      expect(cache.calls, ['import:false']);

      cache.calls.clear();
      google.error = Exception('HTTP 409');
      await vm.importSchedule(); // 409 counts as success, as before
      expect(cache.lastImport?.success, isTrue);
      vm.dispose();
    });

    test('match found: the candidate is saved with the id of the created match', () async {
      final vm = MatchFoundViewModel(
        userId: 1,
        currentGapId: 1,
        candidate: MatchCandidate(proposerGap: _gap(1, 1), acceptorGap: _gap(2, 2), score: 0.5),
        selectedMode: MatchModeEnum.career,
        matchService: FakeMatchService(),
        localCache: cache,
        outbox: outbox,
      );

      final match = await vm.connect();
      expect(match?.id, 42);
      expect(cache.lastCandidateMatchId, 42);
      vm.dispose();
    });

    test('match found: connecting many times without network leaves one pending action', () async {
      final service = FakeMatchService()..error = const SocketException('no network');
      final vm = MatchFoundViewModel(
        userId: 1,
        currentGapId: 1,
        candidate: MatchCandidate(proposerGap: _gap(1, 1), acceptorGap: _gap(2, 2), score: 0.5),
        selectedMode: MatchModeEnum.career,
        matchService: service,
        localCache: cache,
        outbox: outbox,
      );

      expect(await vm.connect(), isNull);
      expect(vm.takeNotice(), MatchFoundViewModel.offlineNotice);
      expect(vm.isConnectPending, isTrue);

      for (var i = 0; i < 8; i++) {
        expect(await vm.connect(), isNull);
      }

      final rows = await outboxRows();
      expect(rows, hasLength(1));
      expect(rows.single['type'], 'match_connect');
      expect(rows.single['dedupe_key'], 'match_connect:1-2');
      expect(rows.single['endpoint'], MatchService.requestEndpoint(1, 2, 0.5));
      expect(vm.errorMessage, isNull);
      vm.dispose();
    });

    test('google import: a network failure shows the offline state with the last saved import', () async {
      await GoogleImportStore().save(GoogleImportState(date: DateTime(2026, 1, 2), success: true, message: 'ok'));
      final google = FakeGoogleService()..error = const SocketException('no network');
      final vm = GoogleCalendarViewModel(googleService: google, localCache: MiguelLocalCache());

      await vm.importSchedule();
      expect(vm.phase, GoogleImportPhase.offline);
      expect(vm.lastImport?.success, isTrue);
      vm.dispose();
    });
  });
}
