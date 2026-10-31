import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/seen_candidates_dao.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_found_view_model.dart';

class _OfflineMatchService extends MatchService {
  List<Match> userMatches = [];

  @override
  Future<Match> sendRequest(int proposerGapId, int acceptorGapId, double score) async {
    throw const SocketException('no network');
  }

  @override
  Future<List<Match>> getUserMatches(int userId) async => userMatches;
}

Gap _gap(int id, int userId) => Gap(
      id: id,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      userId: userId,
      user: User(id: userId, name: 'Ana $userId', email: 'a@test.com', career: 'Systems', interests: []),
    );

MatchCandidate _candidate(int acceptorGapId) =>
    MatchCandidate(proposerGap: _gap(1, 1), acceptorGap: _gap(acceptorGapId, acceptorGapId), score: 0.5);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late SeenCandidatesDao dao;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = SeenCandidatesDao(database: () async => db);
  });

  tearDown(() => db.close());

  Future<List<int>> savedIds() async =>
      (await db.query('seen_candidates', columns: ['match_id'], orderBy: 'match_id ASC')).map((r) => r['match_id'] as int).toList();

  group('seen_candidates keeps only the last rows', () {
    test('after more than ${SeenCandidatesDao.maxRows} candidates only the last ones stay', () async {
      for (var id = 1; id <= 25; id++) {
        await dao.save(id, _candidate(id + 100));
      }

      final ids = await savedIds();
      expect(ids, hasLength(SeenCandidatesDao.maxRows));
      expect(ids.first, 6); // the 5 oldest were deleted
      expect(ids.last, 25);
      expect(await dao.getById(1), isNull);
      expect(await dao.getById(25), isNotNull);
    });

    test('saving the same match again does not add a row', () async {
      await dao.save(7, _candidate(2));
      await dao.save(7, _candidate(2));

      expect(await savedIds(), [7]);
    });
  });

  group('the candidate is saved when the request is queued', () {
    late OutboxService outbox;
    late _OfflineMatchService service;
    late MatchFoundViewModel vm;
    late int backStatus;

    final queuedKey = SeenCandidatesDao.queuedKey(1, 2);

    setUp(() {
      backStatus = 201;
      outbox = OutboxService.forTesting(
        database: () async => db,
        send: (m, e, b) async => http.Response('', backStatus),
      );
      service = _OfflineMatchService();
      vm = MatchFoundViewModel(
        userId: 1,
        currentGapId: 1,
        candidate: _candidate(2),
        selectedMode: MatchModeEnum.career,
        matchService: service,
        localCache: MiguelLocalCache(seenCandidates: dao),
        outbox: outbox,
      )..init();
    });

    tearDown(() async {
      vm.dispose();
      await outbox.dispose();
    });

    // The cache writes without waiting: give it time
    Future<void> settle() => Future.delayed(const Duration(milliseconds: 150));

    test('queueing it saves the candidate with a key that is not a match id', () async {
      expect(await vm.connect(), isNull);
      await settle();

      expect(queuedKey, isNegative);
      expect(await savedIds(), [queuedKey]);
      expect((await dao.getById(queuedKey))?.acceptorGap.user?.name, 'Ana 2');
    });

    test('when the request is confirmed the real match id replaces the queued one', () async {
      service.userMatches = [
        Match(
          id: 7,
          startTime: DateTime(2026, 1, 1, 10),
          endTime: DateTime(2026, 1, 1, 11),
          status: MatchStatusEnum.PENDING,
          proposerGapId: 1,
          acceptorGapId: 2,
        ),
      ];
      await vm.connect();
      await outbox.flush();
      for (var i = 0; i < 200 && !vm.wasSent; i++) {
        await Future.delayed(const Duration(milliseconds: 10));
      }
      await settle();

      expect(vm.wasSent, isTrue);
      expect(await savedIds(), [7]);
    });

    test('cancelling the request forgets the queued candidate', () async {
      await vm.connect();
      await settle();
      expect(await savedIds(), [queuedKey]);

      await vm.cancelRequest();
      await settle();

      expect(await savedIds(), isEmpty);
    });
  });
}
