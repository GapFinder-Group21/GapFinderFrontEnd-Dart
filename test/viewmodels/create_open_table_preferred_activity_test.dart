import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:gapfinderfrontend_dart/models/activity.dart';
import 'package:gapfinderfrontend_dart/models/building.dart';
import 'package:gapfinderfrontend_dart/models/enums/effort_type_enum.dart';
import 'package:gapfinderfrontend_dart/models/responses/preferred_activity_response.dart';
import 'package:gapfinderfrontend_dart/services/activity_service.dart';
import 'package:gapfinderfrontend_dart/services/building_service.dart';
import 'package:gapfinderfrontend_dart/services/preferred_activity_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/create_open_table_view_model.dart';

import 'secure_storage_mock.dart';

Activity _activity(int id, String name, int minutes) =>
    Activity(id: id, name: name, durationMinutes: minutes, effortType: EffortTypeEnum.LOW);

class FakeActivityService extends ActivityService {
  @override
  Future<List<Activity>> getActivities() async =>
      [_activity(1, 'Chess', 30), _activity(2, 'Soccer', 60), _activity(3, 'Coffee', 20)];
}

class FakeBuildingService extends BuildingService {
  @override
  Future<List<Building>> getBuildings() async =>
      [Building(id: 1, name: 'ML', latitude: 0, longitude: 0, radiusMeters: 50)];
}

class FakePreferredActivityService extends PreferredActivityService {
  PreferredActivityResponse? answer = const PreferredActivityResponse(activityId: 2, activityName: 'Soccer', timesChosen: 4);
  Object? error;
  Completer<void>? gate; // keeps the answer waiting, to prove it does not hold the wizard
  int calls = 0;

  @override
  Future<PreferredActivityResponse> getPreferredActivity(int userId) async {
    calls++;
    await gate?.future;
    if (error != null) throw error!;
    return answer ?? const PreferredActivityResponse.none();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  late FakePreferredActivityService preferred;
  late CreateOpenTableViewModel vm;

  setUp(() {
    storage.install();
    storage.setUserId(1);
    SharedPreferences.setMockInitialValues({});
    preferred = FakePreferredActivityService();
    vm = CreateOpenTableViewModel(
      activityService: FakeActivityService(),
      buildingService: FakeBuildingService(),
      preferredActivityService: preferred,
    );
  });

  tearDown(() {
    vm.dispose();
    storage.uninstall();
  });

  group('response', () {
    test('reads the activity of the user from the answer of the back', () {
      final response = PreferredActivityResponse.fromJson({
        'ranking': [],
        'userPreferredActivity': {'activityId': 7, 'activityName': 'Chess', 'timesChosen': 3},
      });
      expect(response.activityId, 7);
      expect(response.timesChosen, 3);
      expect(response.hasPreferred, isTrue);
    });

    test('a user without open tables has no preferred activity', () {
      expect(PreferredActivityResponse.fromJson({'ranking': [], 'userPreferredActivity': null}).hasPreferred, isFalse);
      expect(PreferredActivityResponse.fromJson({}).hasPreferred, isFalse);
    });
  });

  group('wizard preselection', () {
    test('with connection the favorite activity is selected with its duration and the label shows', () async {
      await vm.init();
      await settle();

      expect(vm.selectedActivity?.id, 2);
      expect(vm.isPreferredActivitySelected, isTrue);
      // The answer was saved for the next time without connection
      expect((await SharedPreferences.getInstance()).getInt('preferred_activity_1'), 2);
    });

    test('the answer never holds the wizard: it opens with the first activity and the favorite arrives later', () async {
      preferred.gate = Completer<void>();

      await vm.init();
      expect(vm.isLoading, isFalse);
      expect(vm.selectedActivity?.id, 1);
      expect(vm.isPreferredActivitySelected, isFalse);

      preferred.gate!.complete();
      await settle();
      expect(vm.selectedActivity?.id, 2);
    });

    test('no preferred activity (null) or a failure keeps the first activity', () async {
      preferred.answer = null;
      await vm.init();
      await settle();
      expect(vm.selectedActivity?.id, 1);
      expect(vm.isPreferredActivitySelected, isFalse);
    });

    test('a failure of the back keeps the first activity when nothing was saved', () async {
      preferred.error = Exception('boom');
      await vm.init();
      await settle();
      expect(vm.selectedActivity?.id, 1);
    });

    // Same path as having no connection: the answer is not available, so the last one saved is used
    test('a failure of the back uses the last favorite saved in SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({'preferred_activity_1': 3});
      preferred.error = Exception('no connection');

      await vm.init();
      await settle();

      expect(vm.selectedActivity?.id, 3);
      expect(vm.isPreferredActivitySelected, isTrue);
    });

    test('J-21: an unknown user (404) keeps the saved favorite instead of forgetting it', () async {
      SharedPreferences.setMockInitialValues({'preferred_activity_1': 3});
      preferred.error = PreferredActivityUnknownUserException(1);

      await vm.init();
      await settle();

      expect(vm.selectedActivity?.id, 3);
      expect((await SharedPreferences.getInstance()).getInt('preferred_activity_1'), 3);
    });

    test('when the back says the user has none, the saved one is forgotten', () async {
      SharedPreferences.setMockInitialValues({'preferred_activity_1': 3});
      preferred.answer = null;

      await vm.init();
      await settle();

      expect((await SharedPreferences.getInstance()).containsKey('preferred_activity_1'), isFalse);
    });

    test('a favorite that is not in the catalog is ignored', () async {
      preferred.answer = const PreferredActivityResponse(activityId: 99);
      await vm.init();
      await settle();
      expect(vm.selectedActivity?.id, 1);
    });

    test('the favorite never replaces an activity the user picked', () async {
      preferred.gate = Completer<void>();
      await vm.init();

      vm.selectActivity(vm.activities[2]); // the user picks Coffee before the answer arrives
      preferred.gate!.complete();
      await settle();

      expect(vm.selectedActivity?.id, 3);
    });
  });
}
