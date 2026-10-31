import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_found_view_model.dart';

// Without network on connect(), so the request is queued; getUserMatches answers what the test sets
class _FakeMatchService extends MatchService {
  List<Match> userMatches = [];
  Object? userMatchesError;
  int userMatchesCalls = 0;

  @override
  Future<Match> sendRequest(int proposerGapId, int acceptorGapId, double score) async {
    throw const SocketException('no network');
  }

  @override
  Future<List<Match>> getUserMatches(int userId) async {
    userMatchesCalls++;
    if (userMatchesError != null) throw userMatchesError!;
    return userMatches;
  }
}

Gap _gap(int id, int userId) => Gap(
      id: id,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      userId: userId,
      user: User(id: userId, name: 'Ana $userId', email: 'a@test.com', career: 'Systems', interests: []),
    );

Match _match({MatchStatusEnum status = MatchStatusEnum.PENDING, int proposer = 1, int acceptor = 2}) => Match(
      id: 7,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      status: status,
      proposerGapId: proposer,
      acceptorGapId: acceptor,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;
  late _FakeMatchService service;
  late MatchFoundViewModel vm;
  late int backStatus;
  late String backBody;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    backStatus = 201;
    backBody = '';
    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async => http.Response(backBody, backStatus),
    );
    service = _FakeMatchService();
    vm = MatchFoundViewModel(
      userId: 1,
      currentGapId: 1,
      candidate: MatchCandidate(proposerGap: _gap(1, 1), acceptorGap: _gap(2, 2), score: 0.5),
      selectedMode: MatchModeEnum.career,
      matchService: service,
      outbox: outbox,
    )..init();
  });

  tearDown(() async {
    vm.dispose();
    await outbox.dispose();
    await db.close();
  });

  // Queues the connect, lets the back answer and waits until the screen has an outcome
  Future<void> connectAndFlush() async {
    expect(await vm.connect(), isNull);
    expect(vm.isConnectPending, isTrue);

    await outbox.flush();
    for (var i = 0; i < 200 && !vm.wasSent && vm.outcomeMessage == null; i++) {
      await Future.delayed(const Duration(milliseconds: 10));
    }
  }

  group('MatchFoundViewModel queued connect', () {
    test('a refused connect shows the message of the back and is never "sent"', () async {
      backStatus = 422;
      backBody = 'Uno de los gaps ya tiene un match aceptado';

      await connectAndFlush();

      expect(vm.wasSent, isFalse);
      expect(vm.refusalMessage, 'Uno de los gaps ya tiene un match aceptado');
      expect(vm.outcomeMessage, 'Uno de los gaps ya tiene un match aceptado');
      expect(service.userMatchesCalls, 0);
    });

    test('a connect whose gap time already passed shows the reason', () async {
      backStatus = 422;
      backBody = 'El tiempo en común entre los gaps ya pasó';

      await connectAndFlush();

      expect(vm.wasSent, isFalse);
      expect(vm.refusalMessage, 'El tiempo en común entre los gaps ya pasó');
    });

    test('an accepted connect is "sent" once the request is in the matches of the user', () async {
      service.userMatches = [_match()];

      await connectAndFlush();

      expect(vm.wasSent, isTrue);
      expect(vm.refusalMessage, isNull);
      expect(vm.outcomeMessage, isNull);
      expect(service.userMatchesCalls, 1);
    });

    test('a 409 counts as sent only if the request is in the matches of the user', () async {
      backStatus = 409;
      backBody = 'Ya existe una solicitud';
      service.userMatches = [_match(proposer: 5, acceptor: 6)]; // another request, not this one

      await connectAndFlush();

      expect(vm.wasSent, isFalse);
      expect(vm.refusalMessage, MatchFoundViewModel.refusedNotice);
    });

    test('a 409 with the request in the matches of the user is sent', () async {
      backStatus = 409;
      backBody = 'Ya existe una solicitud';
      service.userMatches = [_match()];

      await connectAndFlush();

      expect(vm.wasSent, isTrue);
    });

    test('a rejected request with the same gaps does not count as sent', () async {
      service.userMatches = [_match(status: MatchStatusEnum.REJECTED)];

      await connectAndFlush();

      expect(vm.wasSent, isFalse);
      expect(vm.refusalMessage, MatchFoundViewModel.refusedNotice);
    });

    test('if the matches cannot be asked, it is not "sent" and the user can try again', () async {
      service.userMatchesError = const SocketException('no network');

      await connectAndFlush();

      expect(vm.wasSent, isFalse);
      expect(vm.refusalMessage, isNull);
      expect(vm.outcomeMessage, MatchFoundViewModel.unconfirmedNotice);
      expect(vm.isConnectPending, isFalse);
    });

    test('cancelling the request is not read as a sent request', () async {
      service.userMatches = [_match()];
      expect(await vm.connect(), isNull);

      await vm.cancelRequest();
      await Future.delayed(const Duration(milliseconds: 100));

      expect(vm.wasSent, isFalse);
      expect(service.userMatchesCalls, 0);
    });
  });
}
