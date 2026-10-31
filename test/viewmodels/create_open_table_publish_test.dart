import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gapfinderfrontend_dart/models/activity.dart';
import 'package:gapfinderfrontend_dart/models/building.dart';
import 'package:gapfinderfrontend_dart/models/enums/effort_type_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/services/activity_service.dart';
import 'package:gapfinderfrontend_dart/services/building_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/create_open_table_view_model.dart';

import 'secure_storage_mock.dart';

final _chess = Activity(id: 1, name: 'Chess', durationMinutes: 30, effortType: EffortTypeEnum.LOW);
final _ml = Building(id: 1, name: 'ML', latitude: 0, longitude: 0, radiusMeters: 50);

class _Activities extends ActivityService {
  @override
  Future<List<Activity>> getActivities() async => [_chess];
}

class _Buildings extends BuildingService {
  @override
  Future<List<Building>> getBuildings() async => [_ml];
}

class _SlowTables extends OpenTableService {
  final gate = Completer<void>();
  int created = 0;

  @override
  Future<OpenTable> createOpenTable(int creatorId, int buildingId, OpenTable openTable, File photo) async {
    created++;
    await gate.future;
    return openTable;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  late _SlowTables tables;
  late CreateOpenTableViewModel vm;
  late Directory dir;

  setUp(() async {
    storage.install();
    storage.setUserId(1);
    SharedPreferences.setMockInitialValues({});
    OfflineAwareMixin.recheckConnection = () async => true;
    dir = await Directory.systemTemp.createTemp('gapfinder_publish_test');
    tables = _SlowTables();
    vm = CreateOpenTableViewModel(
      activityService: _Activities(),
      buildingService: _Buildings(),
      openTableService: tables,
    );
    vm.selectActivity(_chess);
    vm.selectBuilding(_ml);
    vm.setPhotoForTest(File('${dir.path}/photo.jpg'));
  });

  tearDown(() async {
    vm.dispose();
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('S-9: a double tap on Publish creates one table only', () async {
    final first = vm.publish('desc');
    final second = await vm.publish('desc');

    expect(second, PublishResult.alreadyPublishing);

    tables.gate.complete();
    expect(await first, PublishResult.published);
    expect(tables.created, 1);
    expect(vm.isPublishing, isFalse);
  });

  test('S-9: the flag is set before the first await', () async {
    final first = vm.publish('desc');

    expect(vm.isPublishing, isTrue);

    tables.gate.complete();
    await first;
  });

  test('S-8: saved catalogs on screen do not block Publish while the phone is connected', () {
    vm.markFromCache(DateTime.now().subtract(const Duration(days: 2)));

    expect(vm.isOffline, isTrue);
    expect(vm.showingSavedData, isTrue);
    expect(vm.canPublish, isTrue);
  });
}
