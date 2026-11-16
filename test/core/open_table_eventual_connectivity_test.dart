import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_outbox.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';
import 'package:gapfinderfrontend_dart/services/session_cleanup.dart';

// Fake back for the create request; it remembers the tables it saved
class _FakeTables extends OpenTableService {
  final List<Map<String, dynamic>> sent = [];
  final List<OpenTable> saved = [];
  int status = 201;
  bool networkDown = false;
  // The back saves the table but the answer never arrives
  bool loseAnswer = false;

  @override
  Future<List<OpenTable>> getAll() async {
    if (networkDown) throw const SocketException('no network');
    return saved;
  }

  @override
  Future<http.Response> postCreate(Map<String, dynamic> payload, File photo) async {
    if (networkDown) throw const SocketException('no network');
    sent.add(payload);
    if (status == 201) {
      saved.add(OpenTable.fromJson({
        ...payload,
        'id': saved.length + 1,
        'creator': {'id': (payload['creator'] as Map)['id'], 'name': 'Ana'},
        'building': {'id': (payload['building'] as Map)['id'], 'name': 'ML', 'latitude': 0, 'longitude': 0, 'radiusMeters': 50},
      }));
    }
    if (loseAnswer) throw TimeoutException('answer lost');
    return http.Response.bytes(utf8.encode(status == 201 ? '{}' : '{"error":"Datos inválidos"}'), status);
  }
}

void main() {
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;
  late _FakeTables tables;
  late Directory dir;
  late DateTime now;
  late List<int> codes;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    codes = [];
    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async =>
          http.Response.bytes(utf8.encode('{"error":"La mesa está llena"}'), codes.isEmpty ? 200 : codes.removeAt(0)),
    );
    tables = _FakeTables();
    now = DateTime(2026, 11, 12, 10, 0);
    dir = await Directory.systemTemp.createTemp('gapfinder_ec_test');
    OpenTableOutbox.resolvePath = (rel) async => p.join(dir.path, rel);
    OpenTableOutbox.register(outbox: outbox, service: tables, now: () => now);
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Future<int> count(String table) async =>
      Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM $table')) ?? 0;

  Future<bool> queueJoin({String label = 'Café'}) => outbox.enqueue(
        type: OpenTableOutbox.joinType,
        method: 'POST',
        endpoint: '/open-table-participants/table/7/join?userId=1',
        dedupeKey: OpenTableOutbox.joinKey(1, 7),
        label: label,
      );

  Future<File> photo() async {
    final f = File(p.join(dir.path, 'camera.jpg'));
    await f.writeAsBytes([1, 2, 3]);
    return f;
  }

  Future<bool> queueCreate({int duration = 30}) async => OpenTableOutbox.enqueueCreate(
        userId: 1,
        buildingId: 3,
        buildingName: 'ML',
        table: OpenTable(
          id: 0,
          title: 'Café',
          description: 'd',
          startTime: now,
          endTime: now.add(Duration(minutes: duration)),
          maxParticipants: 4,
          status: OpenTableStatusEnum.OPEN,
        ),
        durationMinutes: duration,
        photo: await photo(),
        openedAt: DateTime(2026, 11, 12, 9, 55),
        outbox: outbox,
        service: tables,
      );

  Future<List<File>> queuedPhotos() async {
    final folder = Directory(p.join(dir.path, OpenTableOutbox.photosFolder));
    if (!await folder.exists()) return [];
    return folder.listSync().whereType<File>().toList();
  }

  group('join / leave', () {
    test('a queued join announces the table title when it is sent', () async {
      final deliveries = <OutboxDelivery>[];
      final sub = outbox.deliveries.listen(deliveries.add);

      expect(await queueJoin(), isTrue);
      await outbox.flush();
      await Future<void>.delayed(Duration.zero);

      expect(deliveries.single.label, 'Café');
      expect(deliveries.single.type, OpenTableOutbox.joinType);
      expect(await count('outbox_labels'), 0);
      await sub.cancel();
    });

    test('a refused join brings its label and is not announced as sent', () async {
      final deliveries = <OutboxDelivery>[];
      final refusals = <OutboxRefusal>[];
      final s1 = outbox.deliveries.listen(deliveries.add);
      final s2 = outbox.refusals.listen(refusals.add);
      codes = [422];

      await queueJoin();
      await outbox.flush();
      await Future<void>.delayed(Duration.zero);

      expect(refusals.single.label, 'Café');
      expect(refusals.single.message, 'La mesa está llena');
      expect(deliveries, isEmpty);
      await s1.cancel();
      await s2.cancel();
    });

    test('cancelling a pending join removes its label', () async {
      await queueJoin();
      await outbox.cancelPending(OpenTableOutbox.joinKey(1, 7));

      expect(await count('outbox'), 0);
      expect(await count('outbox_labels'), 0);
    });

    test('many taps without internet leave one row', () async {
      expect(await queueJoin(), isTrue);
      expect(await queueJoin(), isFalse);
      expect(await count('outbox'), 1);
    });
  });

  group('create table', () {
    test('it is queued once with a copy of the photo', () async {
      expect(await queueCreate(), isTrue);
      expect(await queueCreate(), isFalse);

      expect(await count('outbox'), 1);
      expect((await queuedPhotos()).length, 1);
      final pending = await outbox.pendingActions();
      expect(pending.single.label, 'Café en ML');
    });

    test('when the network is back it is published with times from that moment and the photo is deleted', () async {
      final deliveries = <OutboxDelivery>[];
      final sub = outbox.deliveries.listen(deliveries.add);
      await queueCreate();
      now = now.add(const Duration(minutes: 10));

      await outbox.flush();
      await Future<void>.delayed(Duration.zero);

      final sent = tables.sent.single;
      expect(DateTime.parse(sent['startTime'] as String), now);
      expect(DateTime.parse(sent['endTime'] as String), now.add(const Duration(minutes: 30)));
      expect(sent['creator'], {'id': 1});
      expect(sent['building'], {'id': 3});
      expect(await count('outbox'), 0);
      expect(await queuedPhotos(), isEmpty);
      expect(deliveries.single.label, 'Café en ML');
      await sub.cancel();
    });

    test('a network failure keeps the table waiting with its photo', () async {
      await queueCreate();
      tables.networkDown = true;

      await outbox.flush();

      expect(await count('outbox'), 1);
      expect((await queuedPhotos()).length, 1);
      expect(await outbox.isPending(OpenTableOutbox.createKey(1, DateTime(2026, 11, 12, 9, 55))), isTrue);
    });

    test('a send whose answer was lost is not created twice on the next try', () async {
      final deliveries = <OutboxDelivery>[];
      final sub = outbox.deliveries.listen(deliveries.add);
      await queueCreate();
      now = DateTime.now();

      // First try: the back saves it but the phone never gets the answer
      tables.loseAnswer = true;
      await outbox.flush();
      expect(await count('outbox'), 1);

      // Next try: the table is found in the back, so it is not sent again
      tables.loseAnswer = false;
      await outbox.flush();
      await Future<void>.delayed(Duration.zero);

      expect(tables.sent.length, 1);
      expect(tables.saved.length, 1);
      expect(await count('outbox'), 0);
      expect(await queuedPhotos(), isEmpty);
      expect(deliveries.single.label, 'Café en ML');
      await sub.cancel();
    });

    test('a refusal of the back is reported and never counts as published', () async {
      final deliveries = <OutboxDelivery>[];
      final refusals = <OutboxRefusal>[];
      final s1 = outbox.deliveries.listen(deliveries.add);
      final s2 = outbox.refusals.listen(refusals.add);
      await queueCreate();
      tables.status = 400;

      await outbox.flush();
      await Future<void>.delayed(Duration.zero);

      expect(refusals.single.label, 'Café en ML');
      expect(refusals.single.message, 'Datos inválidos');
      expect(deliveries, isEmpty);
      expect(await count('outbox'), 0);
      expect(await queuedPhotos(), isEmpty);
      await s1.cancel();
      await s2.cancel();
    });

    test('a table that waited longer than its activity is not published', () async {
      final refusals = <OutboxRefusal>[];
      final sub = outbox.refusals.listen(refusals.add);
      await queueCreate(duration: 30);
      // queuedAt is the real clock; the handler clock jumps well past it
      now = DateTime.now().add(const Duration(minutes: 31));

      await outbox.flush();
      await Future<void>.delayed(Duration.zero);

      expect(tables.sent, isEmpty);
      expect(refusals.single.message, OpenTableOutbox.expiredMessage);
      expect(await queuedPhotos(), isEmpty);
      await sub.cancel();
    });
  });

  group('logout warning', () {
    test('lists pending actions by name and leaves out silent stats', () async {
      await queueJoin(label: 'Fútbol');
      await queueCreate();
      await outbox.enqueue(type: 'app_session', method: 'POST', endpoint: '/app-sessions', body: {'a': 1});

      final warning = await SessionCleanup.describe(
        pending: outbox.pendingActions,
        hasUnpublishedPhoto: () async => true,
        isOffline: true,
      );

      expect(warning.unsent, ['Unirte a la mesa «Fútbol»', 'Publicar la mesa «Café en ML»']);
      expect(warning.isOffline, isTrue);
      expect(warning.savedData.last, contains('foto'));
    });

    test('clearAll removes the labels too', () async {
      await queueJoin();
      await outbox.clearAll();
      expect(await count('outbox_labels'), 0);
      expect(jsonEncode(await outbox.pendingActions()), '[]');
    });
  });
}
