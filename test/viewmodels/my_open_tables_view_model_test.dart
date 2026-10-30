import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/open_table_participant_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/my_open_tables_view_model.dart';

import 'secure_storage_mock.dart';

User _user(int id) => User(id: id, name: 'user$id', email: 'u$id@test.com', career: 'Systems');

OpenTable _table(int id, int creatorId) {
  final now = DateTime.now();
  return OpenTable(
    id: id,
    title: 'Mesa $id',
    description: 'Descripción',
    startTime: now.subtract(const Duration(minutes: 30)),
    endTime: now.add(const Duration(hours: 1)),
    maxParticipants: 4,
    status: OpenTableStatusEnum.OPEN,
    creator: _user(creatorId),
  );
}

class FakeOpenTableService extends OpenTableService {
  List<OpenTable> all = [];
  int calls = 0;

  @override
  Future<List<OpenTable>> getAll() async {
    calls++;
    return all;
  }
}

class FakeParticipantService extends OpenTableParticipantService {
  List<OpenTable> joined = [];
  int joinedCalls = 0;
  int perTableCalls = 0;

  @override
  Future<List<OpenTable>> getJoinedOpenTables(int userId) async {
    joinedCalls++;
    return joined;
  }

  // The old way: one request per table. The screen must never use it again.
  @override
  Future<List<OpenTableParticipant>> getByOpenTable(int tableId) async {
    perTableCalls++;
    return [];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  late FakeOpenTableService tables;
  late FakeParticipantService participants;

  setUp(() {
    storage.install();
    storage.values['userId'] = '7';
    tables = FakeOpenTableService();
    participants = FakeParticipantService();
  });

  tearDown(storage.uninstall);

  test('with 325 tables in the database it uses two requests and never one per table', () async {
    // The seed data has about 325 tables: 2 created by the user, 3 joined, the rest from other people
    tables.all = [
      for (var id = 1; id <= 325; id++) _table(id, id <= 2 ? 7 : 100 + id),
    ];
    participants.joined = [_table(10, 101), _table(20, 102), _table(30, 103)];
    final vm = MyOpenTablesViewModel(openTableService: tables, participantService: participants);

    await vm.init();

    expect(vm.createdTables.map((t) => t.id), [1, 2]);
    expect(vm.joinedTables.map((t) => t.id), [10, 20, 30]);
    expect(tables.calls, 1);
    expect(participants.joinedCalls, 1);
    expect(participants.perTableCalls, 0);
    expect(vm.error, isNull);
    vm.dispose();
  });

  test('a table created by the user never shows as joined', () async {
    tables.all = [_table(1, 7)];
    participants.joined = [_table(1, 7), _table(2, 50)];
    final vm = MyOpenTablesViewModel(openTableService: tables, participantService: participants);

    await vm.init();

    expect(vm.createdTables.map((t) => t.id), [1]);
    expect(vm.joinedTables.map((t) => t.id), [2]);
    vm.dispose();
  });
}
