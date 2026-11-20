import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart' show Sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_mode_outbox.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_period_dao.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';

http.Response _json(int code, Object body) => http.Response.bytes(utf8.encode(jsonEncode(body)), code);
http.Response _text(int code, String body) => http.Response.bytes(utf8.encode(body), code);

StudyPeriod _period(String clientId) => StudyPeriod(
      clientId: clientId,
      userId: 1,
      startTime: DateTime(2026, 11, 23, 10),
      endTime: DateTime(2026, 11, 23, 11),
      gapId: 4,
    );

void main() {
  sqfliteFfiInit();
  late Database db;
  late OutboxService outbox;
  late StudyPeriodDao dao;

  // What the handler sent to the back, and what the fake back answers next
  late List<String> posts;
  late List<Map<String, dynamic>> postBodies;
  late List<String> gets;
  late List<String> deletes;
  late List<http.Response> postAnswers;
  late http.Response getAnswer;
  late List<String> genericRequests; // rows without a handler (the DELETE of a removal)
  // Runs while the POST is "in flight" (to cancel the row at that moment)
  Future<void> Function()? duringPost;

  Future<int> outboxRows() async => Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM outbox')) ?? 0;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = StudyPeriodDao(database: () async => db);

    posts = [];
    postBodies = [];
    gets = [];
    deletes = [];
    postAnswers = [];
    getAnswer = _json(200, []);
    genericRequests = [];
    duringPost = null;

    outbox = OutboxService.forTesting(
      database: () async => db,
      send: (method, endpoint, body) async {
        genericRequests.add('$method $endpoint');
        return _text(204, '');
      },
    );
    StudyModeOutbox.register(
      outbox: outbox,
      dao: dao,
      post: (path, body) async {
        posts.add(path);
        postBodies.add(body);
        if (duringPost != null) await duringPost!();
        return postAnswers.isEmpty ? _json(201, {'id': 7}) : postAnswers.removeAt(0);
      },
      get: (path) async {
        gets.add(path);
        return getAnswer;
      },
      delete: (path) async {
        deletes.add(path);
        return _text(204, '');
      },
    );
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
  });

  test('the key and the endpoints', () {
    expect(StudyModeOutbox.key(1, 'abc'), 'study_mode:1:abc');
    expect(StudyModeOutbox.clientIdOf('study_mode:1:abc', 1), 'abc');
    expect(StudyModeOutbox.clientIdOf('study_mode:2:abc', 1), isNull); // another user's key
    expect(StudyModeOutbox.clientIdOf('match_rating:1:abc', 1), isNull);
    expect(StudyModeOutbox.endpoint(1), '/users/1/study-mode');
    expect(StudyModeOutbox.periodEndpoint(1, 9), '/users/1/study-mode/9');
  });

  test('queueing the same period twice leaves one row (dedupe key)', () async {
    await dao.upsert(_period('a'));

    expect(await StudyModeOutbox.enqueueAdd(_period('a'), outbox: outbox), isTrue);
    expect(await StudyModeOutbox.enqueueAdd(_period('a'), outbox: outbox), isFalse);

    expect(await outboxRows(), 1);
  });

  test('the POST carries the period without the user id, and the back id is saved in SQLite (synced)', () async {
    await dao.upsert(_period('a'));
    await StudyModeOutbox.enqueueAdd(_period('a'), outbox: outbox);

    await outbox.flush();

    expect(posts, ['/users/1/study-mode']);
    expect(postBodies.single, {
      'startTime': '2026-11-23T10:00:00',
      'endTime': '2026-11-23T11:00:00',
      'gapId': 4,
      'clientId': 'a',
    });
    expect(await outboxRows(), 0);
    final saved = (await dao.find('a'))!;
    expect(saved.synced, isTrue);
    expect(saved.serverId, 7);
  });

  test('a 409 means the back already had it: its id is looked up in the list', () async {
    await dao.upsert(_period('a'));
    await StudyModeOutbox.enqueueAdd(_period('a'), outbox: outbox);
    postAnswers = [_text(409, 'Este periodo de estudio ya fue registrado')];
    getAnswer = _json(200, [
      {'id': 3, 'clientId': 'other'},
      {'id': 9, 'clientId': 'a'},
    ]);

    await outbox.flush();

    expect(gets, ['/users/1/study-mode']);
    expect(await outboxRows(), 0);
    final saved = (await dao.find('a'))!;
    expect(saved.synced, isTrue);
    expect(saved.serverId, 9);
  });

  test('a refusal (422) drops the row, saves the reason and leaves the period for the screen to remove', () async {
    await dao.upsert(_period('a'));
    await StudyModeOutbox.enqueueAdd(_period('a'), outbox: outbox);
    postAnswers = [_text(422, 'Esta persona no puede activar el modo estudio')];

    await outbox.flush();

    expect(await outboxRows(), 0);
    final refusal = await outbox.lastRefusalFor(StudyModeOutbox.key(1, 'a'));
    expect(refusal?.message, 'Esta persona no puede activar el modo estudio');
    expect((await dao.find('a'))!.synced, isFalse);
  });

  test('an unreadable refusal uses the message of the app', () async {
    await dao.upsert(_period('a'));
    await StudyModeOutbox.enqueueAdd(_period('a'), outbox: outbox);
    postAnswers = [_text(400, '<html>Bad request</html>')];

    await outbox.flush();

    final refusal = await outbox.lastRefusalFor(StudyModeOutbox.key(1, 'a'));
    expect(refusal?.message, StudyModeOutbox.refusedMessage);
  });

  test('a server error is not final: the row stays and counts one attempt', () async {
    await dao.upsert(_period('a'));
    await StudyModeOutbox.enqueueAdd(_period('a'), outbox: outbox);
    postAnswers = [_text(500, 'boom')];

    await outbox.flush();

    expect(await outboxRows(), 1);
    final row = (await db.query('outbox')).single;
    expect(row['attempts'], 1);
    expect((await dao.find('a'))!.synced, isFalse);
  });

  test('if the user removed the period while it was being sent, the back is told to forget it', () async {
    await dao.upsert(_period('a'));
    await StudyModeOutbox.enqueueAdd(_period('a'), outbox: outbox);
    // The user taps "Quitar" at the moment the POST is on its way
    duringPost = () => outbox.cancelPending(StudyModeOutbox.key(1, 'a'));

    await outbox.flush();

    expect(deletes, ['/users/1/study-mode/7']);
    expect((await dao.find('a'))!.synced, isFalse); // nothing was marked: the screen removes it
  });

  test('removing a period the back has is a plain DELETE row', () async {
    await StudyModeOutbox.enqueueRemove(1, 'a', 9, outbox: outbox);

    final row = (await db.query('outbox')).single;
    expect(row['type'], StudyModeOutbox.removeType);
    expect(row['method'], 'DELETE');
    expect(row['endpoint'], '/users/1/study-mode/9');
    expect(row['dedupe_key'], 'study_mode:1:a');

    await outbox.flush();

    expect(genericRequests, ['DELETE /users/1/study-mode/9']);
    expect(await outboxRows(), 0);
    expect(posts, isEmpty); // the handler of the POST is not used for it
  });
}
