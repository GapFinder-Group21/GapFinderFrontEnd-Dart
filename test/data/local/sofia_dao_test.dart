import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/class_block_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/gap_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_cache_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_detail_dao.dart';
import 'package:gapfinderfrontend_dart/models/activity.dart';
import 'package:gapfinderfrontend_dart/models/building.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/models/enums/day_of_week_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/effort_type_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/models/responses/recommendation_response.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';

OpenTable _table(int id) => OpenTable(
      id: id,
      title: 'Table $id',
      description: 'desc',
      startTime: DateTime(2026, 5, 1, 10),
      endTime: DateTime(2026, 5, 1, 11),
      maxParticipants: 4,
      status: OpenTableStatusEnum.OPEN,
      createdAt: DateTime(2026, 5, 1, 9),
      activity: Activity(id: 1, name: 'Chess', durationMinutes: 60, effortType: EffortTypeEnum.LOW),
      creator: User(id: 7, name: 'Ana', email: 'ana@x.com', career: 'ISIS'),
      building: Building(id: 3, name: 'ML', latitude: 4.6, longitude: -74.0, radiusMeters: 50),
      photoUrl: '/photos/$id.jpg',
    );

void main() {
  sqfliteFfiInit();

  late Database db;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await AppDatabase.createModuleTables(db);
  });

  tearDown(() => db.close());

  test('class blocks are replaced for the user and read back', () async {
    final dao = ClassBlockDao(database: () async => db);
    ClassBlock block(int id) => ClassBlock(
          id: id,
          subject: 'Math',
          location: 'ML 101',
          dayOfWeek: DayOfWeekEnum.TUE,
          startTime: const TimeOfDay(hour: 8, minute: 30),
          endTime: const TimeOfDay(hour: 10, minute: 0),
        );

    await dao.replaceAllForUser(1, [block(1), block(2)]);
    await dao.replaceAllForUser(2, [block(3)]);
    await dao.replaceAllForUser(1, [block(4)]);

    final mine = await dao.getAllForUser(1);
    expect(mine.map((b) => b.id), [4]);
    expect(mine.first.startTime, const TimeOfDay(hour: 8, minute: 30));
    expect(mine.first.dayOfWeek, DayOfWeekEnum.TUE);
    expect((await dao.getAllForUser(2)).length, 1);
    expect(await dao.getById(3), isNotNull);
    expect(await dao.lastSavedAt(1), isNotNull);
    expect(await dao.lastSavedAt(99), isNull);
  });

  test('gaps are replaced for the user and read back', () async {
    final dao = GapDao(database: () async => db);
    Gap gap(int id) => Gap(id: id, startTime: DateTime(2026, 5, 1, 12), endTime: DateTime(2026, 5, 1, 13));

    await dao.replaceAllForUser(1, [gap(1), gap(2)]);
    await dao.replaceAllForUser(1, [gap(3)]);

    final gaps = await dao.getAllForUser(1);
    expect(gaps.map((g) => g.id), [3]);
    expect(gaps.first.startTime, DateTime(2026, 5, 1, 12));
    expect(gaps.first.userId, 1);
    expect(await dao.lastSavedAt(1), isNotNull);
  });

  test('ALL and MINE lists are independent, even for the same table', () async {
    final dao = OpenTableCacheDao(database: () async => db);

    await dao.replaceAll(OpenTableListType.all, [_table(1), _table(2)]);
    await dao.replaceAll(OpenTableListType.mine, [_table(1)]);
    expect((await dao.getAll(OpenTableListType.all)).map((t) => t.id), [1, 2]);
    expect((await dao.getAll(OpenTableListType.mine)).map((t) => t.id), [1]);

    await dao.replaceAll(OpenTableListType.all, [_table(5)]);
    expect((await dao.getAll(OpenTableListType.all)).map((t) => t.id), [5]);
    expect((await dao.getAll(OpenTableListType.mine)).length, 1);

    final back = (await dao.getById(5))!;
    expect(back.creator?.name, 'Ana');
    expect(back.building?.name, 'ML');
    expect(back.activity?.name, 'Chess');
    expect(back.photoUrl, '/photos/5.jpg');
    expect(await dao.lastSavedAt(OpenTableListType.mine), isNotNull);
  });

  test('the detail keeps the table and its participants', () async {
    final dao = OpenTableDetailDao(database: () async => db);
    final participant = OpenTableParticipant(
      id: 1,
      joinedAt: DateTime(2026, 5, 1, 10, 5),
      openTableId: 1,
      userId: 8,
      user: User(id: 8, name: 'Leo', email: 'leo@x.com', career: 'IIND'),
    );

    await dao.save(_table(1), [participant]);
    await dao.save(_table(1), [participant, participant]);

    final record = (await dao.getById(1))!;
    expect(record.table.title, 'Table 1');
    expect(record.participants.length, 2);
    expect(record.participants.first.user?.name, 'Leo');
    expect(await dao.getAll(), hasLength(1));
    expect(await dao.lastSavedAt(1), isNotNull);
    expect(await dao.getById(99), isNull);
  });

  test('a recommendation can be read back from its JSON', () {
    final response = RecommendationResponse(
      buildingId: 3,
      buildingName: 'ML',
      totalMinutes: 42.5,
      tables: [_table(1)],
    );

    final back = RecommendationResponse.fromJson(response.toJson());
    expect(back.buildingName, 'ML');
    expect(back.totalMinutes, 42.5);
    expect(back.tables.single.creator?.id, 7);
  });
}
