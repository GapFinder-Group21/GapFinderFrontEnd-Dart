import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/open_table_participant_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/open_tables_view_model.dart';

import 'secure_storage_mock.dart';

User _user(int id) => User(id: id, name: 'user$id', email: 'u$id@test.com', career: 'Systems');

OpenTable _table(int id) {
  final now = DateTime.now();
  return OpenTable(
    id: id,
    title: 'Mesa $id',
    description: 'Descripción',
    startTime: now.subtract(const Duration(minutes: 30)),
    endTime: now.add(const Duration(hours: 1)),
    maxParticipants: 4,
    status: OpenTableStatusEnum.OPEN,
    creator: _user(100),
  );
}

// Every call to getAll waits for its own completer, so a test decides which answer arrives first
class _ControlledTables extends OpenTableService {
  final calls = <Completer<List<OpenTable>>>[];

  @override
  Future<List<OpenTable>> getAll() {
    final c = Completer<List<OpenTable>>();
    calls.add(c);
    return c.future;
  }
}

class _Participants extends OpenTableParticipantService {
  final Set<int> failingTables = {};
  final Set<int> joinedTables = {};

  @override
  Future<List<OpenTableParticipant>> getByOpenTable(int tableId) async {
    if (failingTables.contains(tableId)) throw Exception('timeout');
    if (!joinedTables.contains(tableId)) return [];
    return [OpenTableParticipant(id: tableId, joinedAt: DateTime.now(), user: _user(7))];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  const geolocator = MethodChannel('flutter.baseflow.com/geolocator');
  late _ControlledTables tables;
  late _Participants participants;
  late OpenTablesViewModel vm;

  setUp(() {
    storage.install();
    storage.values['userId'] = '7';

    // The GPS is on and the permission is granted (LocationPermission.always)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      geolocator,
      (call) async {
        if (call.method == 'isLocationServiceEnabled') return true;
        if (call.method == 'checkPermission') return 3;
        return null;
      },
    );

    tables = _ControlledTables();
    participants = _Participants();
    vm = OpenTablesViewModel(openTableService: tables, participantService: participants);
  });

  tearDown(() {
    vm.dispose();
    storage.uninstall();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(geolocator, null);
  });

  // Lets the started load reach its network call
  Future<void> reachNetwork(int callNumber) async {
    for (var i = 0; i < 100 && tables.calls.length < callNumber; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(tables.calls.length, callNumber);
  }

  test('S-12: when two loads overlap, the last one to start wins even if the first finishes later', () async {
    final first = vm.refresh();
    await reachNetwork(1);
    final second = vm.refresh();
    await reachNetwork(2);

    // The newer load answers first; the old one answers afterwards with an old list
    tables.calls[1].complete([_table(2)]);
    await second;
    tables.calls[0].complete([_table(1)]);
    await first;

    expect(vm.openTables.map((t) => t.id), [2]);
    expect(vm.isLoading, isFalse);
  });

  test('S-12: the old load finishing first does not show its list', () async {
    final first = vm.refresh();
    await reachNetwork(1);
    final second = vm.refresh();
    await reachNetwork(2);

    tables.calls[0].complete([_table(1)]);
    await first;
    expect(vm.openTables, isEmpty);

    tables.calls[1].complete([_table(2)]);
    await second;
    expect(vm.openTables.map((t) => t.id), [2]);
  });

  test('S-18: a failed membership check is "unknown" and not "not joined"', () async {
    participants.failingTables.add(2);
    participants.joinedTables.add(1);

    final load = vm.refresh();
    await reachNetwork(1);
    tables.calls[0].complete([_table(1), _table(2), _table(3)]);
    await load;

    expect(vm.isMember(_table(1)), isTrue);
    expect(vm.isMembershipUnknown(_table(1)), isFalse);

    expect(vm.isMember(_table(2)), isFalse);
    expect(vm.isMembershipUnknown(_table(2)), isTrue);

    expect(vm.isMember(_table(3)), isFalse);
    expect(vm.isMembershipUnknown(_table(3)), isFalse);
  });
}
