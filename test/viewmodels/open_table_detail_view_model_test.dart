import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/open_table_participant_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/open_table_detail_view_model.dart';

import 'secure_storage_mock.dart';

User _user(int id) =>
    User(id: id, name: 'user$id', email: 'u$id@test.com', career: 'Systems');

OpenTable _table({
  int maxParticipants = 3,
  OpenTableStatusEnum status = OpenTableStatusEnum.OPEN,
  Duration endsIn = const Duration(hours: 1),
}) {
  final now = DateTime.now();
  return OpenTable(
    id: 1,
    title: 'Study table',
    description: 'Calculus',
    startTime: now.subtract(const Duration(minutes: 30)),
    endTime: now.add(endsIn),
    maxParticipants: maxParticipants,
    status: status,
    creator: _user(1),
  );
}

OpenTableParticipant _participant(int userId) => OpenTableParticipant(
      id: userId,
      joinedAt: DateTime(2026, 1, 1),
      userId: userId,
      user: _user(userId),
    );

class FakeOpenTableService extends OpenTableService {
  late OpenTable table;
  Object? error;
  int calls = 0;

  @override
  Future<OpenTable> getOpenTable(int id) async {
    calls++;
    if (error != null) throw error!;
    return table;
  }
}

class FakeParticipantService extends OpenTableParticipantService {
  List<OpenTableParticipant> participants = [];
  Object? joinError;
  int joins = 0;

  @override
  Future<List<OpenTableParticipant>> getByOpenTable(int tableId) async =>
      participants;

  @override
  Future<OpenTableParticipant> join(int tableId, int userId) async {
    joins++;
    if (joinError != null) throw joinError!;
    final p = _participant(userId);
    participants = [...participants, p];
    return p;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  late FakeOpenTableService tables;
  late FakeParticipantService participants;
  late OpenTableDetailViewModel vm;

  setUp(() {
    // The cache is static, so a table saved by one test would answer the next one
    OpenTableDetailViewModel.clearCache();
    storage.install();
    storage.setUserId(1);
    tables = FakeOpenTableService()..table = _table();
    participants = FakeParticipantService();
    vm = OpenTableDetailViewModel(
      1,
      openTableService: tables,
      participantService: participants,
    );
  });

  tearDown(() {
    vm.dispose();
    storage.uninstall();
  });

  group('OpenTableDetailViewModel', () {
    test('initial state: loading and no table', () {
      expect(vm.isLoading, isTrue);
      expect(vm.table, isNull);
      expect(vm.participants, isEmpty);
      expect(vm.loadError, isNull);
      expect(vm.isMember, isFalse);
    });

    test('init() loads the table, participants, isCreator and isMember',
        () async {
      participants.participants = [_participant(1), _participant(2)];

      await vm.init();

      expect(vm.isLoading, isFalse);
      expect(vm.loadError, isNull);
      expect(vm.table?.title, 'Study table');
      expect(vm.participants, hasLength(2));
      expect(vm.isCreator, isTrue);
      expect(vm.isMember, isTrue);
      expect(vm.hasUser, isTrue);
    });

    test('loadError is set when the service throws', () async {
      tables.error = Exception('not found');

      await vm.init();

      expect(vm.isLoading, isFalse);
      expect(vm.loadError, contains('not found'));
      expect(vm.table, isNull);
    });

    test('isFull is true when the table has max participants', () async {
      tables.table = _table(maxParticipants: 2);
      participants.participants = [_participant(2), _participant(3)];

      await vm.init();

      expect(vm.isFull, isTrue);
    });

    test('isFull is false while there is room and hasEnded is false',
        () async {
      participants.participants = [_participant(2)];

      await vm.init();

      expect(vm.isFull, isFalse);
      expect(vm.hasEnded, isFalse);
    });

    test('hasEnded is true when the end time has passed', () async {
      tables.table = _table(endsIn: const Duration(minutes: -5));

      await vm.init();

      expect(vm.hasEnded, isTrue);
    });

    test('join() returns null and the user becomes a member', () async {
      await vm.init();
      expect(vm.isMember, isFalse);

      expect(await vm.join(), isNull);
      await settle();

      expect(participants.joins, 1);
      expect(vm.isJoining, isFalse);
      expect(vm.isMember, isTrue);
    });

    test('join() returns the error message when the service throws', () async {
      participants.joinError = Exception('Table is full');
      await vm.init();

      expect(await vm.join(), 'Table is full');
      await settle();
      expect(vm.isJoining, isFalse);
    });
  });

  group('detailExpiry', () {
    final now = DateTime(2026, 10, 25, 12);

    OpenTableDetailData data({
      required Duration endsIn,
      OpenTableStatusEnum status = OpenTableStatusEnum.OPEN,
    }) {
      final table = OpenTable(
        id: 1,
        title: 'Study table',
        description: '',
        startTime: now.subtract(const Duration(minutes: 30)),
        endTime: now.add(endsIn),
        maxParticipants: 3,
        status: status,
      );
      return OpenTableDetailData(table, []);
    }

    test('a table that ends far away lives 5 minutes', () {
      expect(OpenTableDetailViewModel.detailExpiry(data(endsIn: const Duration(hours: 3)), now),
          const Duration(minutes: 5));
    });

    test('a table that ends in 2 minutes lives 2 minutes', () {
      expect(OpenTableDetailViewModel.detailExpiry(data(endsIn: const Duration(minutes: 2)), now),
          const Duration(minutes: 2));
    });

    test('never less than 30 seconds, even if it ends in 5 seconds or already ended', () {
      expect(OpenTableDetailViewModel.detailExpiry(data(endsIn: const Duration(seconds: 5)), now),
          const Duration(seconds: 30));
      expect(OpenTableDetailViewModel.detailExpiry(data(endsIn: const Duration(minutes: -10)), now),
          const Duration(seconds: 30));
    });

    test('a completed table lives 15 minutes', () {
      expect(
        OpenTableDetailViewModel.detailExpiry(
            data(endsIn: const Duration(minutes: 1), status: OpenTableStatusEnum.COMPLETED), now),
        const Duration(minutes: 15),
      );
    });
  });

  group('errors and pending actions', () {
    test('a network failure while loading shows its own message, not the exception', () async {
      tables.error = const SocketException('Failed host lookup: api');

      await vm.init();

      expect(vm.loadError, isNotNull);
      expect(vm.loadError, isNot(contains('SocketException')));
      expect(vm.loadError, contains('conectar'));
    });

    test('cancelPendingAction with nothing pending changes nothing', () async {
      await vm.init();

      await vm.cancelPendingAction();

      expect(vm.hasPendingAction, isFalse);
      expect(vm.syncError, isNull);
    });
  });

  group('detail cache', () {
    test('opening the same table twice asks the network only once', () async {
      await vm.init();
      expect(tables.calls, 1);

      final second = OpenTableDetailViewModel(1, openTableService: tables, participantService: participants);
      await second.init();
      second.dispose();

      expect(tables.calls, 1);
      expect(second.table?.title, 'Study table');
    });

    test('joining empties the cache entry and reloads from the network', () async {
      await vm.init();
      expect(tables.calls, 1);

      await vm.join();
      await settle();

      expect(tables.calls, 2);
    });
  });
}
