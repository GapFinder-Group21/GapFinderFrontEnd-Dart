import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart' show Sqflite;
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
import 'package:gapfinderfrontend_dart/services/google_service.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/google_calendar_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_found_view_model.dart';

// The POST takes too long; getUserMatches answers what the test sets
class _SlowMatchService extends MatchService {
  List<Match> userMatches = [];
  Object? userMatchesError;

  @override
  Future<Match> sendRequest(int proposerGapId, int acceptorGapId, double score) async {
    throw TimeoutException('too slow');
  }

  @override
  Future<List<Match>> getUserMatches(int userId) async {
    if (userMatchesError != null) throw userMatchesError!;
    return userMatches;
  }
}

class _SlowGoogleService extends GoogleService {
  @override
  Future<bool> importSchedule() async => throw TimeoutException('too slow');
}

Gap _gap(int id, int userId) => Gap(
      id: id,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      userId: userId,
      user: User(id: userId, name: 'Ana $userId', email: 'a@test.com', career: 'Systems', interests: []),
    );

Match _createdMatch() => Match(
      id: 7,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      status: MatchStatusEnum.PENDING,
      proposerGapId: 1,
      acceptorGapId: 2,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;
  late _SlowMatchService service;
  late MatchFoundViewModel vm;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    outbox = OutboxService.forTesting(database: () async => db, send: (m, e, b) async => http.Response('', 200));
    service = _SlowMatchService();
    vm = MatchFoundViewModel(
      userId: 1,
      currentGapId: 1,
      candidate: MatchCandidate(proposerGap: _gap(1, 1), acceptorGap: _gap(2, 2), score: 0.5),
      selectedMode: MatchModeEnum.career,
      matchService: service,
      localCache: MiguelLocalCache(seenCandidates: SeenCandidatesDao(database: () async => db)),
      outbox: outbox,
    );
  });

  tearDown(() async {
    vm.dispose();
    await outbox.dispose();
    await db.close();
  });

  Future<int> rowCount() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  group('match found: a slow answer is not "offline"', () {
    test('if the request already exists after the timeout it is the answer and nothing is queued', () async {
      service.userMatches = [_createdMatch()];

      final match = await vm.connect();

      expect(match?.id, 7); // the screen goes to the waiting screen
      expect(await rowCount(), 0);
      expect(vm.isConnectPending, isFalse);
    });

    test('if it does not exist it is queued with a message about the slow answer', () async {
      final match = await vm.connect();

      expect(match, isNull);
      expect(vm.takeNotice(), MatchFoundViewModel.slowNotice);
      expect(vm.isConnectPending, isTrue);
      expect(await rowCount(), 1);
    });

    test('if the matches cannot be asked either it is queued', () async {
      service.userMatchesError = http.ClientException('no network');

      expect(await vm.connect(), isNull);
      expect(await rowCount(), 1);
      expect(vm.errorMessage, isNull);
    });
  });

  group('google import: a timeout does not say it needs a connection', () {
    test('it shows the slow message in the error state, with retry', () async {
      final google = GoogleCalendarViewModel(googleService: _SlowGoogleService(), localCache: MiguelLocalCache());

      await google.importSchedule();

      expect(google.phase, GoogleImportPhase.error);
      expect(google.errorMessage, GoogleCalendarViewModel.slowMessage);
      expect(google.errorMessage, isNot(contains('conexión')));
      expect(google.canRetry, isTrue);
      google.dispose();
    });
  });
}
