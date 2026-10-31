import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;
  late List<int> statusCodes; // answers of the fake back, one per request
  late List<String> sent; // "METHOD endpoint" of every request that reached the fake back

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);

    statusCodes = [];
    sent = [];
    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async {
        sent.add('$method $endpoint');
        return http.Response('', statusCodes.isEmpty ? 200 : statusCodes.removeAt(0));
      },
    );
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
  });

  Future<int> rowCount() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  Future<bool> join({String? key = 'join-1', bool replace = false, Map<String, dynamic>? body}) {
    return outbox.enqueue(
      type: 'join',
      method: 'POST',
      endpoint: '/open-table-participants/table/1/join',
      body: body,
      dedupeKey: key,
      replaceIfPending: replace,
    );
  }

  group('OutboxService', () {
    test('enqueue with the same dedupeKey does not duplicate the action', () async {
      expect(await join(), isTrue);
      expect(await join(), isFalse);
      expect(await join(), isFalse);

      expect(await rowCount(), 1);
      expect(await outbox.isPending('join-1'), isTrue);
    });

    test('actions without dedupeKey are all saved', () async {
      await join(key: null);
      await join(key: null);

      expect(await rowCount(), 2);
    });

    test('replaceIfPending replaces the body of the pending action', () async {
      await join(body: {'v': 1});

      expect(await join(replace: true, body: {'v': 2}), isTrue);

      final rows = await db.query('outbox');
      expect(rows, hasLength(1));
      expect(rows.first['body'], '{"v":2}');
    });

    test('cancelPending removes the action', () async {
      await join();

      await outbox.cancelPending('join-1');

      expect(await rowCount(), 0);
      expect(await outbox.isPending('join-1'), isFalse);
      expect(await join(), isTrue); // the same key can be saved again
    });

    test('flush sends in creation order and deletes the sent rows', () async {
      await outbox.enqueue(type: 'a', method: 'POST', endpoint: '/first');
      await outbox.enqueue(type: 'b', method: 'DELETE', endpoint: '/second');

      await outbox.flush();

      expect(sent, ['POST /first', 'DELETE /second']);
      expect(await rowCount(), 0);
    });

    test('a 409 answer counts as sent', () async {
      statusCodes = [409];
      await join();

      await outbox.flush();

      expect(await rowCount(), 0);
    });

    test('a failure adds an attempt and keeps the error; after 5 it is not retried', () async {
      statusCodes = List.filled(10, 500, growable: true);
      await join();

      for (var i = 0; i < 7; i++) {
        await outbox.flush();
      }

      final row = (await db.query('outbox')).single;
      expect(row['attempts'], OutboxService.maxAttempts);
      expect(row['last_error'], contains('500'));
      expect(sent, hasLength(OutboxService.maxAttempts));
      expect(await outbox.isPending('join-1'), isFalse);
    });

    test('a registered handler is used instead of the API', () async {
      var handled = 0;
      outbox.registerHandler('photo', (row) async {
        handled++;
        return true;
      });
      await outbox.enqueue(type: 'photo', method: 'POST', endpoint: '/photo');

      await outbox.flush();

      expect(handled, 1);
      expect(sent, isEmpty);
      expect(await rowCount(), 0);
    });

    test('nothing is sent and no attempt is used while offline', () async {
      final offline = OutboxService.forTesting(
        database: () async => db,
        send: (method, endpoint, body) async => http.Response('', 200),
        isOnline: () async => false,
      );
      await join();

      await offline.flush();

      final row = (await db.query('outbox')).single;
      expect(row['attempts'], 0);
    });

    test('pendingKeys and pendingCount reflect the table', () async {
      await join();

      expect(await outbox.pendingKeys.first, {'join-1'});
      expect(await outbox.pendingCount.first, 1);
    });

    test('a network error does not use an attempt and stops the rest of the flush', () async {
      final calls = <String>[];
      final flaky = OutboxService.forTesting(
        database: () async => db,
        send: (method, endpoint, body) async {
          calls.add(endpoint);
          throw const SocketException('no route');
        },
      );
      await join(key: 'a');
      await join(key: 'b');

      await flaky.flush();

      final rows = await db.query('outbox', orderBy: 'id');
      expect(rows.map((r) => r['attempts']), [0, 0]);
      expect(calls, hasLength(1)); // the second one was not even tried
    });

    test('a 4xx answer drops the row: the back refused it for good', () async {
      statusCodes = [400];
      await join();

      await outbox.flush();

      expect(await rowCount(), 0);
      expect(await outbox.isPending('join-1'), isFalse);
    });

    test('401, 403, 408 and 429 are retried, not dropped', () async {
      statusCodes = [401, 403, 408, 429];
      await join();

      for (var i = 0; i < 4; i++) {
        await outbox.flush();
      }

      final row = (await db.query('outbox')).single;
      expect(row['attempts'], 4);
    });

    test('a 5xx answer still adds an attempt', () async {
      statusCodes = [503];
      await join();

      await outbox.flush();

      expect((await db.query('outbox')).single['attempts'], 1);
    });

    test('with flushOnEnqueue the action leaves right after it is saved', () async {
      final eager = OutboxService.forTesting(
        database: () async => db,
        send: (method, endpoint, body) async {
          sent.add('$method $endpoint');
          return http.Response('', 200);
        },
        flushOnEnqueue: true,
      );

      await eager.enqueue(type: 'join', method: 'POST', endpoint: '/x', dedupeKey: 'k');
      // Not a fixed sleep: wait until the send happened (up to 5 s) so a slow machine does not fail the test
      for (var i = 0; i < 100 && (sent.isEmpty || await rowCount() != 0); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }

      expect(sent, ['POST /x']);
      expect(await rowCount(), 0);
    });
  });
}
