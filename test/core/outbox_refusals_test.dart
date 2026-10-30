import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';

http.Response answer(int status, String body) =>
    http.Response.bytes(utf8.encode(body), status, headers: {'content-type': 'text/plain; charset=utf-8'});

void main() {
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;
  late Future<http.Response> Function(String method, String endpoint, Map<String, dynamic>? body) handler;
  late List<String> sent;

  Future<int> rowCount() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  OutboxService build({Duration timeout = OutboxService.sendTimeout, Duration? retryDelay}) {
    return OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) {
        sent.add('$method $endpoint');
        return handler(method, endpoint, body);
      },
      sendTimeout: timeout,
      retryDelay: retryDelay,
    );
  }

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    sent = [];
    handler = (m, e, b) async => answer(200, '');
    outbox = build();
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
  });

  Future<bool> queue(String key, {String endpoint = '/join', Map<String, dynamic>? body}) {
    return outbox.enqueue(type: 'join', method: 'POST', endpoint: endpoint, body: body, dedupeKey: key);
  }

  group('the back refuses an action (422)', () {
    test('the row is deleted and the refusal is saved with the Spanish text of the back', () async {
      handler = (m, e, b) async => answer(422, 'La open table está llena');
      await queue('join-1');

      await outbox.flush();

      expect(await rowCount(), 0);
      final refusal = await outbox.lastRefusalFor('join-1');
      expect(refusal, isNotNull);
      expect(refusal!.message, 'La open table está llena');
      expect(refusal.type, 'join');
    });

    test('the refusal is emitted on the refusals stream', () async {
      handler = (m, e, b) async => answer(422, 'La open table ya terminó');
      await queue('join-2');
      final emitted = outbox.refusals.first;

      await outbox.flush();

      final refusal = await emitted.timeout(const Duration(seconds: 2));
      expect(refusal.key, 'join-2');
      expect(refusal.message, 'La open table ya terminó');
    });

    test('a refusal that looks technical is replaced by a message of our own', () async {
      handler = (m, e, b) async => answer(422, 'java.lang.IllegalStateException at com.backend.X');
      await queue('join-3');

      await outbox.flush();

      final refusal = await outbox.lastRefusalFor('join-3');
      expect(refusal!.message, 'El servidor no aceptó la acción');
    });

    test('the text can come in a JSON with "error"', () async {
      handler = (m, e, b) async => answer(422, '{"error":"El tiempo en común ya pasó"}');
      await queue('connect-1');

      await outbox.flush();

      expect((await outbox.lastRefusalFor('connect-1'))!.message, 'El tiempo en común ya pasó');
    });

    test('a new action with the same key forgets the old refusal', () async {
      handler = (m, e, b) async => answer(422, 'La open table está llena');
      await queue('join-1');
      await outbox.flush();
      expect(await outbox.lastRefusalFor('join-1'), isNotNull);

      await queue('join-1');

      expect(await outbox.lastRefusalFor('join-1'), isNull);
    });
  });

  group('409 is not a refusal', () {
    test('a 409 counts as done: no refusal is saved', () async {
      handler = (m, e, b) async => answer(409, 'El usuario ya está registrado en esta open table');
      await queue('join-1');

      await outbox.flush();

      expect(await rowCount(), 0);
      expect(await outbox.lastRefusalFor('join-1'), isNull);
    });
  });

  group('flush', () {
    test('an action saved while a flush is running is sent by that same flush', () async {
      final firstSend = Completer<http.Response>();
      var call = 0;
      handler = (m, e, b) {
        call++;
        return call == 1 ? firstSend.future : Future.value(answer(200, ''));
      };
      await queue('a', endpoint: '/a');

      final flushing = outbox.flush(); // the first request is held
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await queue('b', endpoint: '/b'); // saved while the flush is running
      unawaited(outbox.flush()); // the real app calls flush on every enqueue: it must not be lost
      firstSend.complete(answer(200, ''));
      await flushing;
      await Future<void>.delayed(const Duration(milliseconds: 100));

      expect(sent, ['POST /a', 'POST /b']);
      expect(await rowCount(), 0);
    });

    test('an action cancelled while an earlier one is in flight is never sent', () async {
      final firstSend = Completer<http.Response>();
      var call = 0;
      handler = (m, e, b) {
        call++;
        return call == 1 ? firstSend.future : Future.value(answer(200, ''));
      };
      await queue('a', endpoint: '/a');
      await queue('b', endpoint: '/b');

      final flushing = outbox.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await outbox.cancelPending('b'); // the user cancels b while a is being sent
      firstSend.complete(answer(200, ''));
      await flushing;

      expect(sent, ['POST /a']);
    });

    test('the body replaced while an earlier row is in flight is the one that is sent', () async {
      final firstSend = Completer<http.Response>();
      final bodies = <Map<String, dynamic>?>[];
      var call = 0;
      handler = (m, e, b) {
        call++;
        bodies.add(b);
        return call == 1 ? firstSend.future : Future.value(answer(200, ''));
      };
      await queue('a', endpoint: '/a');
      await outbox.enqueue(
          type: 'save', method: 'POST', endpoint: '/b', body: {'v': 1}, dedupeKey: 'b', replaceIfPending: true);

      final flushing = outbox.flush();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await outbox.enqueue(
          type: 'save', method: 'POST', endpoint: '/b', body: {'v': 2}, dedupeKey: 'b', replaceIfPending: true);
      firstSend.complete(answer(200, ''));
      await flushing;

      expect(bodies.last, {'v': 2});
    });

    test('a request that takes too long is a network failure: no attempt is used and it is tried again', () async {
      await outbox.dispose();
      outbox = build(timeout: const Duration(milliseconds: 50), retryDelay: const Duration(milliseconds: 200));
      var call = 0;
      handler = (m, e, b) {
        call++;
        return call == 1 ? Completer<http.Response>().future : Future.value(answer(200, ''));
      };
      await queue('join-1');

      await outbox.flush();
      expect(await rowCount(), 1);
      final attempts = Sqflite.firstIntValue(await db.rawQuery('SELECT attempts FROM outbox'));
      expect(attempts, 0);

      await Future<void>.delayed(const Duration(milliseconds: 600)); // the retry timer fires
      expect(await rowCount(), 0);
      expect(sent.length, 2);
    });
  });

  group('clearAll', () {
    test('removes the pending actions and the refusals', () async {
      handler = (m, e, b) async => answer(422, 'La open table está llena');
      await queue('join-1');
      await outbox.flush();
      await queue('join-2');

      await outbox.clearAll();

      expect(await rowCount(), 0);
      expect(await outbox.lastRefusalFor('join-1'), isNull);
      expect(await outbox.isPending('join-2'), isFalse);
    });
  });
}
