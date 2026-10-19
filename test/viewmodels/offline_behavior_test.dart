import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/responses/auth_response.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/login_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/friends_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_invitation_view_model.dart';

import 'noop_local_cache.dart';
import 'secure_storage_mock.dart';

// Connectivity that the test controls
class FakeConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool online;

  FakeConnectivity({this.online = true});

  void setOnline(bool value) {
    online = value;
    _controller.add(value);
  }

  @override
  bool get isOnline => online;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  @override
  Future<bool> checkNow() async => online;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}

class FakeAuthService extends AuthService {
  int calls = 0;

  @override
  Future<AuthResponse> login(String email, String password) async {
    calls++;
    return AuthResponse(id: 1, accessToken: 'a', refreshToken: 'r', email: email, name: 'Test');
  }
}

class FakeMatchService extends MatchService {
  @override
  Future<Match> getById(int id) async => Match(
        id: id,
        startTime: DateTime(2026, 1, 1, 10),
        endTime: DateTime(2026, 1, 1, 11),
        status: MatchStatusEnum.PENDING,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final storage = SecureStorageMock();
  late Database db;
  late OutboxService outbox;
  late FakeConnectivity connectivity;

  Future<int> rowCount() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  setUp(() async {
    storage.install();
    storage.setUserId(1);
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async => throw UnimplementedError('nothing is sent in these tests'),
      isOnline: () async => false,
    );
    connectivity = FakeConnectivity(online: false);
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
    storage.uninstall();
  });

  group('login (network only)', () {
    test('without connection it does not call the back and says why', () async {
      final auth = FakeAuthService();
      final vm = LoginViewModel(authService: auth, localCache: NoopLocalCache(), connectivity: connectivity);

      expect(vm.isOffline, isTrue);
      expect(await vm.login('ana@test.com', 'secret'), isFalse);
      expect(vm.errorMessage, 'Necesitas conexión para iniciar sesión');
      expect(vm.isLoading, isFalse);
      expect(auth.calls, 0);

      connectivity.setOnline(true);
      await settle();
      expect(vm.isOffline, isFalse);
      expect(await vm.login('ana@test.com', 'secret'), isTrue);
      vm.dispose();
    });
  });

  group('friends (queued actions)', () {
    late FriendsViewModel vm;

    setUp(() {
      vm = FriendsViewModel(localCache: NoopLocalCache(), connectivity: connectivity, outbox: outbox);
    });

    tearDown(() => vm.dispose());

    test('accepting the same request many times without connection leaves one pending action', () async {
      await vm.init();
      expect(vm.isOffline, isTrue);

      for (var i = 0; i < 5; i++) {
        expect(await vm.acceptRequest(7), isTrue);
      }
      // Reject shares the key with accept: it does not add a second decision
      expect(await vm.rejectRequest(7), isTrue);
      await settle();

      expect(await rowCount(), 1);
      expect(vm.isDecisionPending(7), isTrue);
      expect(vm.lastActionQueued, isTrue);
    });

    test('sending a request to the same user many times leaves one pending action', () async {
      await vm.init();
      for (var i = 0; i < 5; i++) {
        expect(await vm.sendFriendRequest(9), isTrue);
      }
      await settle();

      expect(await rowCount(), 1);
      expect(vm.isSendPending(9), isTrue);
      expect(vm.isSendPending(10), isFalse);
    });

    test('search is ignored without connection', () async {
      await vm.init();
      await vm.search('ana');
      expect(vm.isSearching, isFalse);
    });
  });

  group('match invitation (queued answer)', () {
    test('accepting many times without connection leaves one pending action', () async {
      connectivity.online = true;
      final vm = MatchInvitationViewModel(
        5,
        matchService: FakeMatchService(),
        localCache: NoopLocalCache(),
        connectivity: connectivity,
        outbox: outbox,
      );
      expect(await vm.init(), isTrue);
      expect(vm.match, isNotNull);

      connectivity.setOnline(false);
      await settle();
      expect(vm.isOffline, isTrue);

      for (var i = 0; i < 4; i++) {
        expect(await vm.accept(), InvitationAnswer.queued);
      }
      expect(await vm.decline(), InvitationAnswer.queued);
      await settle();

      expect(await rowCount(), 1);
      expect(vm.isPending, isTrue);
      vm.dispose();
    });
  });
}
