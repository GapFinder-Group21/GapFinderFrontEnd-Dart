import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/seen_candidates_dao.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

Gap _gap(int id, int userId) => Gap(
      id: id,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      userId: userId,
      user: User(
        id: userId,
        name: 'Ana $userId',
        email: 'a@test.com',
        career: 'Systems',
        avatarUrl: 'https://example.com/avatar-$userId.png',
        interests: [],
      ),
    );

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
  });

  tearDown(() => db.close());

  group('a saved match candidate keeps the nested user', () {
    test('the name and the avatar of both gaps come back after saving and reading it', () async {
      final dao = SeenCandidatesDao(database: () async => db);
      await dao.save(5, MatchCandidate(proposerGap: _gap(1, 1), acceptorGap: _gap(2, 2), score: 0.75));

      final saved = await dao.getById(5);

      expect(saved?.proposerGap.user?.name, 'Ana 1');
      expect(saved?.acceptorGap.user?.name, 'Ana 2');
      expect(saved?.acceptorGap.user?.avatarUrl, 'https://example.com/avatar-2.png');
      expect(saved?.score, 0.75);
    });
  });
}
