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

  @override
  Future<OpenTable> getOpenTable(int id) async {
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
}
