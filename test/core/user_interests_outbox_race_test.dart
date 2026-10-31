import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_outbox.dart';

void main() {
  sqfliteFfiInit();

  late Database db;
  late OutboxService outbox;
  late UserInterestsDao dao;
  late List<String> posts;
  // Runs inside the first POST: it is the user saving again while the flush is sending
  Future<void> Function()? duringFirstPost;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = UserInterestsDao(database: () async => db);
    outbox = OutboxService.forTesting(database: () async => db, send: (m, e, b) async => http.Response('', 200));
    posts = [];
    duringFirstPost = null;

    UserInterestsOutbox.register(
      outbox: outbox,
      dao: dao,
      post: (path) async {
        posts.add(path);
        final hook = duringFirstPost;
        duringFirstPost = null;
        if (hook != null) await hook();
        return http.Response('', 200);
      },
    );
  });

  tearDown(() async {
    await outbox.dispose();
    await db.close();
  });

  Future<List<Map<String, Object?>>> outboxRows() => db.query('outbox');

  group('user interests outbox race', () {
    test('a selection saved while another is being sent is not lost', () async {
      await dao.replaceAllForUser(1, {1, 2}, {});
      await UserInterestsOutbox.enqueue(1, {1, 2}, outbox: outbox);

      duringFirstPost = () async {
        // The user saves {3}: SQLite has it at once and the pending row gets the new body
        await dao.replaceAllForUser(1, {3}, {});
        await UserInterestsOutbox.enqueue(1, {3}, outbox: outbox);
      };

      await outbox.flush();

      // The row of {1, 2} was not deleted: it holds {3}, and SQLite was not overwritten with {1, 2}
      final rows = await outboxRows();
      expect(rows, hasLength(1));
      expect(rows.single['body'], contains('[3]'));
      expect((await dao.getAllForUser(1)).map((r) => r.interestId), [3]);
      expect((await dao.getAllForUser(1)).single.synced, isFalse);

      await outbox.flush();

      expect(posts, ['/users/1/interests/1', '/users/1/interests/2', '/users/1/interests/3']);
      expect(await outboxRows(), isEmpty);
      final saved = await dao.getAllForUser(1);
      expect(saved.map((r) => r.interestId), [3]);
      expect(saved.single.synced, isTrue);
    });

    test('without a new save the row is deleted and SQLite is marked synced', () async {
      await dao.replaceAllForUser(1, {1, 2}, {});
      await UserInterestsOutbox.enqueue(1, {1, 2}, outbox: outbox);

      await outbox.flush();

      expect(await outboxRows(), isEmpty);
      final saved = await dao.getAllForUser(1);
      expect(saved.map((r) => r.interestId), [1, 2]);
      expect(saved.every((r) => r.synced), isTrue);
    });
  });
}
