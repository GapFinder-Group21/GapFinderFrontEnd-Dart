import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_found_view_model.dart';

class _OfflineMatchService extends MatchService {
  @override
  Future<Match> sendRequest(int proposerGapId, int acceptorGapId, double score) async {
    throw const SocketException('no network');
  }
}

Gap _gap(int id, int userId) => Gap(
      id: id,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      userId: userId,
      user: User(id: userId, name: 'Ana $userId', email: 'a@test.com', career: 'Systems', interests: []),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;
  late List<String> sent;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    sent = [];
    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async {
        sent.add('$method $endpoint');
        return http.Response('', 200);
      },
    );
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
  });

  MatchFoundViewModel buildVm() => MatchFoundViewModel(
        userId: 1,
        currentGapId: 1,
        candidate: MatchCandidate(proposerGap: _gap(1, 1), acceptorGap: _gap(2, 2), score: 0.5),
        selectedMode: MatchModeEnum.career,
        matchService: _OfflineMatchService(),
        outbox: outbox,
      );

  Future<int> rowCount() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  group('MatchFoundViewModel.cancelRequest', () {
    test('a queued connect that is cancelled is never sent', () async {
      final vm = buildVm();

      expect(await vm.connect(), isNull);
      expect(vm.isConnectPending, isTrue);
      expect(await rowCount(), 1);

      await vm.cancelRequest();
      expect(vm.isConnectPending, isFalse);
      expect(await rowCount(), 0);

      await outbox.flush(); // the network returns
      expect(sent, isEmpty);
      expect(vm.wasSent, isFalse);
      vm.dispose();
    });

    test('with nothing pending it changes nothing', () async {
      final vm = buildVm();

      await vm.cancelRequest();

      expect(vm.isConnectPending, isFalse);
      expect(await rowCount(), 0);
      vm.dispose();
    });

    test('after cancelling, the user can connect again', () async {
      final vm = buildVm();
      await vm.connect();
      await vm.cancelRequest();

      expect(await vm.connect(), isNull);
      expect(vm.isConnectPending, isTrue);
      expect(await rowCount(), 1);
      vm.dispose();
    });
  });
}
