import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/match_history_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/rating_drafts_hive_store.dart';
import 'package:gapfinderfrontend_dart/models/match_history_item.dart';
import 'package:gapfinderfrontend_dart/services/match_rating_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_history_processing.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/my_matches_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

class _FakeConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool online;
  _FakeConnectivity(this.online);

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

Map<String, dynamic> _json(int id, {String status = 'COMPLETED', bool canRate = true, int? my, int? other, int day = 10}) {
  final d = day.toString().padLeft(2, '0');
  return {
    'matchId': id,
    'status': status,
    'startTime': '2026-11-${d}T10:00:00',
    'endTime': '2026-11-${d}T11:00:00',
    'score': 0.7,
    'otherUser': {'id': 2, 'name': 'Ana', 'email': '', 'career': 'Sistemas'},
    'myRating': my == null ? null : {'stars': my, 'comment': null, 'createdAt': '2026-11-${d}T12:00:00'},
    'otherRating': other == null ? null : {'stars': other, 'comment': 'Bien'},
    'canRate': canRate,
  };
}

// Fake back: a rating changes the history the way the real one does
class _FakeRatingService extends MatchRatingService {
  List<Map<String, dynamic>> history = [];
  int historyCalls = 0;
  int rateCalls = 0;
  Object? rateError;

  @override
  Future<String> getHistory(int userId) async {
    historyCalls++;
    return jsonEncode(history);
  }

  @override
  Future<void> rate(int matchId, int stars, String? comment) async {
    rateCalls++;
    final error = rateError;
    if (error != null) throw error;
    final item = history.firstWhere((h) => h['matchId'] == matchId);
    item['myRating'] = {'stars': stars, 'comment': comment, 'createdAt': '2026-11-16T12:00:00'};
    item['canRate'] = false;
  }
}

// Drafts in memory instead of the Hive box
class _MemoryDrafts extends RatingDraftsHiveStore {
  final Map<String, RatingDraft> saved = {};

  @override
  Future<void> save(int userId, int matchId, RatingDraft draft) async =>
      saved[RatingDraftsHiveStore.keyFor(userId, matchId)] = draft;
  @override
  Future<RatingDraft?> load(int userId, int matchId) async => saved[RatingDraftsHiveStore.keyFor(userId, matchId)];
  @override
  Future<void> delete(int userId, int matchId) async => saved.remove(RatingDraftsHiveStore.keyFor(userId, matchId));
  @override
  Future<void> clear() async => saved.clear();
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 80));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;
  late MatchHistoryDao dao;
  late _FakeRatingService service;
  late _MemoryDrafts drafts;
  late _FakeConnectivity connectivity;
  late List<int> outboxCodes; // answers of the back to the outbox, one per request
  late MyMatchesViewModel vm;

  MyMatchesViewModel build({MatchHistoryDao? withDao}) => MyMatchesViewModel(
        service: service,
        dao: withDao ?? dao,
        drafts: drafts,
        outbox: outbox,
        connectivity: connectivity,
        readUserId: () async => 1,
        // Same function the isolate runs, called directly in the test
        process: (payload) async => processMatchHistory(payload),
      );

  Future<int> outboxRows() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  setUp(() async {
    MyMatchesViewModel.clearHistoryCache();
    OfflineAwareMixin.recheckConnection = () async => true;
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = MatchHistoryDao(database: () async => db);
    outboxCodes = [];
    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async {
        final code = outboxCodes.isEmpty ? 201 : outboxCodes.removeAt(0);
        final text = code == 422 ? '{"error":"Este match ya no se puede calificar"}' : '{}';
        return http.Response.bytes(utf8.encode(text), code);
      },
    );
    service = _FakeRatingService()
      ..history = [
        _json(10, day: 12),
        _json(11, day: 5, canRate: false, my: 5, other: 4),
        _json(12, day: 14, status: 'ACCEPTED', canRate: false),
      ];
    drafts = _MemoryDrafts();
    connectivity = _FakeConnectivity(true);
  });

  tearDown(() async {
    vm.dispose();
    await outbox.dispose();
    await db.close();
  });

  // Offline with the history already saved in SQLite
  Future<void> openOffline() async {
    await dao.replaceAllForUser(1, service.history.map(MatchHistoryItem.fromJson).toList());
    connectivity.online = false;
    vm = build();
    await vm.init();
    await _settle();
  }

  test('online: loads the history newest first, the summary and saves it in SQLite', () async {
    vm = build();
    await vm.init();

    expect(vm.error, isNull);
    expect(vm.isOffline, isFalse);
    expect(vm.all.map((i) => i.matchId), [12, 10, 11]);
    expect(vm.filter, MatchHistoryFilter.toRate);
    expect(vm.items.map((i) => i.matchId), [10]);
    expect(vm.averageReceived, 4.0);
    expect(vm.pendingToRate, 1);

    vm.selectFilter(MatchHistoryFilter.rated);
    expect(vm.items.map((i) => i.matchId), [11]);

    await _settle();
    expect(await dao.getAllForUser(1), hasLength(3));
  });

  test('offline: shows the history saved in SQLite with the time it was saved', () async {
    await openOffline();

    expect(service.historyCalls, 0);
    expect(vm.error, isNull);
    expect(vm.isOffline, isTrue);
    expect(vm.lastUpdated, isNotNull);
    expect(vm.all, hasLength(3));
    expect(vm.pendingToRate, 1);
  });

  test('offline with nothing saved: error message instead of an empty list', () async {
    connectivity.online = false;
    vm = build();
    await vm.init();

    expect(vm.error, 'Sin conexión y aún no tenemos tus matches guardados');
  });

  test('opening the screen again uses the LRU cache, without SQLite or the network', () async {
    vm = build();
    await vm.init();
    vm.dispose();

    // A DAO on an empty database and no network: if the history shows, it came from memory
    final emptyDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(emptyDb);
    connectivity.online = false;
    vm = build(withDao: MatchHistoryDao(database: () async => emptyDb));
    await vm.init();

    expect(service.historyCalls, 1);
    expect(vm.all, hasLength(3));
    await emptyDb.close();
  });

  test('the cache lives 1 minute with an ACCEPTED match and 10 minutes without', () {
    vm = build();
    final withAccepted = service.history.map(MatchHistoryItem.fromJson).toList();
    final onlyOld = [MatchHistoryItem.fromJson(_json(1))];

    expect(MyMatchesViewModel.historyExpiry(withAccepted), const Duration(minutes: 1));
    expect(MyMatchesViewModel.historyExpiry(onlyOld), const Duration(minutes: 10));
  });

  test('rating offline goes to the outbox with key match_rating:<userId>:<matchId> and shows as pending', () async {
    await openOffline();
    await vm.saveDraft(10, 4, 'Muy buena');

    expect(await vm.rate(10, 4, 'Muy buena'), isNull);
    await _settle();

    expect(service.rateCalls, 0);
    expect(await outbox.isPending('match_rating:1:10'), isTrue);
    final row = (await db.query('outbox')).single;
    expect(row['type'], 'match_rating');
    expect(row['method'], 'POST');
    expect(row['endpoint'], '/matches/10/ratings');
    expect(jsonDecode(row['body'] as String), {'stars': 4, 'comment': 'Muy buena'});

    // Optimistic: it is already in "Calificados" with my stars and "Pendiente de enviar"
    expect(vm.isPending(10), isTrue);
    final item = vm.all.firstWhere((i) => i.matchId == 10);
    expect(item.myRating?.stars, 4);
    expect(vm.canRateNow(item), isFalse);
    expect(vm.pendingToRate, 0);
    expect(vm.takeNotice(), MyMatchesViewModel.queuedNotice);
    // The draft stays until the rating reaches the back
    expect(await vm.loadDraft(10), isNotNull);
  });

  test('when the outbox sends it the draft is removed and the user is told', () async {
    await openOffline();
    await vm.saveDraft(10, 4, '');
    await vm.rate(10, 4, null);
    vm.takeNotice();
    await _settle();

    await outbox.flush();
    await _settle();

    expect(vm.isPending(10), isFalse);
    expect(vm.all.firstWhere((i) => i.matchId == 10).myRating?.stars, 4);
    expect(vm.takeNotice(), MyMatchesViewModel.sentNotice);
    expect(await vm.loadDraft(10), isNull);
  });

  test('a match cannot be rated twice: offline only one row is queued', () async {
    await openOffline();

    expect(await vm.rate(10, 4, null), isNull);
    expect(await vm.rate(10, 2, 'otra vez'), MyMatchesViewModel.alreadyRated);
    await _settle();

    expect(await outboxRows(), 1);
  });

  test('a match cannot be rated twice: online the second rating is not sent', () async {
    vm = build();
    await vm.init();
    await vm.saveDraft(10, 5, '');

    expect(await vm.rate(10, 5, null), isNull);
    expect(service.rateCalls, 1);
    expect(await vm.loadDraft(10), isNull);
    expect(vm.takeNotice(), MyMatchesViewModel.sentNotice);

    expect(await vm.rate(10, 3, null), MyMatchesViewModel.alreadyRated);
    expect(service.rateCalls, 1);
    // An already rated match (11) and a match that is not completed (12) cannot be rated either
    expect(await vm.rate(11, 3, null), MyMatchesViewModel.alreadyRated);
    expect(await vm.rate(12, 3, null), 'Este match aún no se puede calificar');
  });

  test('online, if the network fails while sending, the rating goes to the outbox', () async {
    service.rateError = const SocketException('no network');
    vm = build();
    await vm.init();

    expect(await vm.rate(10, 3, null), isNull);
    await _settle();

    expect(await outbox.isPending('match_rating:1:10'), isTrue);
    expect(vm.isPending(10), isTrue);
  });

  test('a refusal of the back goes back to "Por calificar" with the reason, keeping the draft', () async {
    await openOffline();
    await vm.saveDraft(10, 2, 'Llegó tarde');
    await vm.rate(10, 2, 'Llegó tarde');
    vm.takeNotice();
    await _settle();

    outboxCodes = [422];
    await outbox.flush();
    await _settle();

    expect(vm.isPending(10), isFalse);
    final item = vm.all.firstWhere((i) => i.matchId == 10);
    expect(item.myRating, isNull);
    expect(vm.canRateNow(item), isTrue);
    expect(vm.items.map((i) => i.matchId), contains(10));
    expect(vm.takeNotice(), 'No se pudo enviar tu calificación: Este match ya no se puede calificar');
    expect((await vm.loadDraft(10))?.comment, 'Llegó tarde');
  });

  test('stars and comment are validated', () async {
    vm = build();
    await vm.init();

    expect(await vm.rate(10, 0, null), 'Elige de 1 a 5 estrellas');
    expect(await vm.rate(10, 4, 'x' * 301), isNotNull);
    expect(service.rateCalls, 0);
  });
}
