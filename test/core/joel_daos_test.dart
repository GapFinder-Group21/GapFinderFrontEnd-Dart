import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/friend_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/friend_request_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/match_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/notification_dao.dart';
import 'package:gapfinderfrontend_dart/models/app_notification.dart';
import 'package:gapfinderfrontend_dart/models/enums/friendship_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/notification_type_enum.dart';
import 'package:gapfinderfrontend_dart/models/friendship.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

User _user(int id, String name) => User(
      id: id,
      name: name,
      email: '$name@test.com',
      career: 'Systems',
      interests: [Interest(id: 1, name: 'Chess')],
    );

void main() {
  sqfliteFfiInit();
  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
  });

  tearDown(() => db.close());

  test('friends: replaceAllForUser replaces only that user rows and keeps nested data', () async {
    final dao = FriendDao(database: () async => db);
    await dao.replaceAllForUser(1, [_user(2, 'ana'), _user(3, 'leo')]);
    await dao.replaceAllForUser(1, [_user(3, 'leo')]);
    await dao.replaceAllForUser(9, [_user(4, 'eva')]);

    final mine = await dao.getAllForUser(1);
    expect(mine.map((u) => u.id), [3]);
    expect(mine.first.interests.first.name, 'Chess');
    expect((await dao.getById(4))?.name, 'eva');
    expect(await dao.lastSavedAt(1), isNotNull);
    expect(await dao.lastSavedAt(5), isNull);
  });

  test('friend_requests keeps the requester', () async {
    final dao = FriendRequestDao(database: () async => db);
    await dao.replaceAllForUser(1, [
      Friendship(
        id: 7,
        status: FriendshipStatusEnum.pending,
        createdAt: DateTime(2026, 1, 1),
        requesterId: 2,
        requester: _user(2, 'ana'),
      ),
    ]);
    expect((await dao.getById(7))?.requester?.name, 'ana');
  });

  test('notifications saves is_read', () async {
    final dao = NotificationDao(database: () async => db);
    await dao.replaceAllForUser(1, [
      AppNotification(
        id: 5,
        type: NotificationTypeEnum.MATCH_PROPOSED,
        message: 'hi',
        read: false,
        createdAt: DateTime(2026, 1, 1),
      ),
    ]);
    final rows = await db.query('notifications');
    expect(rows.single['is_read'], 0);
    expect((await dao.getById(5))?.message, 'hi');
  });

  test('matches saves the gap of the user', () async {
    final dao = MatchDao(database: () async => db);
    final match = Match(
      id: 3,
      startTime: DateTime(2026, 1, 1, 10),
      endTime: DateTime(2026, 1, 1, 11),
      status: MatchStatusEnum.ACCEPTED,
      proposerGapId: 20,
      acceptorGapId: 30,
      acceptorGap: Gap(id: 30, startTime: DateTime(2026, 1, 1, 10), endTime: DateTime(2026, 1, 1, 11)),
    );
    await dao.replaceAllForUserGaps(1, [match], {30});
    expect((await db.query('matches')).single['gap_id'], 30);

    await dao.upsertForUser(1, match, 30);
    final saved = await dao.getAllForUser(1);
    expect(saved.single.acceptorGap?.id, 30);
  });

  test('J-18: savedAtById gives the time of that match, not the newest match of the user', () async {
    final dao = MatchDao(database: () async => db);
    Map<String, Object?> row(int id, String savedAt) => {
          'id': id,
          'user_id': 1,
          'json': '{}',
          'saved_at': savedAt,
          'gap_id': null,
        };
    await dao.upsertRow(row(3, '2026-01-01T10:00:00.000'));
    await dao.upsertRow(row(4, '2026-01-02T18:30:00.000'));

    expect(await dao.savedAtById(3), DateTime(2026, 1, 1, 10));
    expect(await dao.lastSavedAt(1), DateTime(2026, 1, 2, 18, 30));
    expect(await dao.savedAtById(99), isNull);
  });
}
