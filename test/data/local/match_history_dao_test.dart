import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/match_history_dao.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/match_history_item.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

MatchHistoryItem _item(int id, {int? myStars, int? otherStars, bool canRate = false}) => MatchHistoryItem(
      matchId: id,
      status: MatchStatusEnum.COMPLETED,
      startTime: DateTime(2026, 11, id, 10),
      endTime: DateTime(2026, 11, id, 11),
      score: 0.8,
      otherUser: User(id: 2, name: 'Ana', email: 'ana@x.com', career: 'Sistemas'),
      myRating: myStars == null ? null : MatchRating(stars: myStars, comment: 'Genial'),
      otherRating: otherStars == null ? null : MatchRating(stars: otherStars),
      canRate: canRate,
    );

void main() {
  sqfliteFfiInit();
  late Database db;
  late MatchHistoryDao dao;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
    dao = MatchHistoryDao(database: () async => db);
  });

  tearDown(() => db.close());

  test('saves the history of a user and reads it back with the other user and both ratings', () async {
    await dao.replaceAllForUser(1, [_item(3, myStars: 5, otherStars: 4), _item(4, canRate: true)]);

    final saved = await dao.getAllForUser(1);
    expect(saved.map((i) => i.matchId), [3, 4]);
    expect(saved.first.otherUser?.name, 'Ana');
    expect(saved.first.myRating?.stars, 5);
    expect(saved.first.myRating?.comment, 'Genial');
    expect(saved.first.otherRating?.stars, 4);
    expect(saved.last.canRate, isTrue);
    expect(await dao.lastSavedAt(1), isNotNull);
  });

  test('a new answer replaces the old rows of the user', () async {
    await dao.replaceAllForUser(1, [_item(3), _item(4)]);
    await dao.replaceAllForUser(1, [_item(5)]);

    expect((await dao.getAllForUser(1)).map((i) => i.matchId), [5]);
  });

  test('the same match is kept for its two students, and logout removes only that user', () async {
    await dao.replaceAllForUser(1, [_item(7, myStars: 5)]);
    await dao.replaceAllForUser(2, [_item(7, myStars: 2)]);

    expect((await dao.getAllForUser(1)).single.myRating?.stars, 5);
    expect((await dao.getAllForUser(2)).single.myRating?.stars, 2);

    await dao.deleteForUser(1);
    expect(await dao.getAllForUser(1), isEmpty);
    expect(await dao.lastSavedAt(1), isNull);
    expect(await dao.getAllForUser(2), hasLength(1));
  });
}
