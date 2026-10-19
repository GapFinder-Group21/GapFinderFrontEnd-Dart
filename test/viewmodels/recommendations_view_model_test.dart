import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/recommendations_hive_store.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/responses/recommendation_response.dart';
import 'package:gapfinderfrontend_dart/services/recommendation_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/recommendations/recommendations_view_model.dart';

class FakeRecommendationService extends RecommendationService {
  RecommendationResponse? response;
  Object? error;
  int calls = 0;
  int? lastUserId;

  @override
  Future<RecommendationResponse> recommendOpenTables(int userId) async {
    calls++;
    lastUserId = userId;
    if (error != null) throw error!;
    return response!;
  }
}

RecommendationResponse _sampleResponse() {
  final now = DateTime(2026, 1, 1, 10);
  return RecommendationResponse(
    buildingId: 7,
    buildingName: 'Edificio Central',
    totalMinutes: 90,
    tables: [
      OpenTable(
        id: 1,
        title: 'Mesa de estudio',
        description: 'Repaso de calculo',
        startTime: now,
        endTime: now.add(const Duration(hours: 1)),
        maxParticipants: 4,
        status: OpenTableStatusEnum.OPEN,
      ),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Fake of flutter_secure_storage so TokenStorage can run in tests
  final storage = <String, String>{};
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  // Hive saves the last recommendation (cache then network), so it needs a folder in the tests
  setUpAll(() => Hive.init(Directory.systemTemp.createTempSync('hive_recommendations').path));

  setUp(() async {
    storage.clear();
    await (await Hive.openBox(RecommendationsHiveStore.boxName)).clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final key = call.arguments['key'] as String?;
      switch (call.method) {
        case 'read':
          return storage[key];
        case 'write':
          storage[key!] = call.arguments['value'] as String;
          return null;
        case 'delete':
          storage.remove(key);
          return null;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('RecommendationsViewModel', () {
    test('initial state: loading, no data and no error', () {
      final vm = RecommendationsViewModel(
        recommendationService: FakeRecommendationService(),
      );

      expect(vm.isLoading, isTrue);
      expect(vm.recommendation, isNull);
      expect(vm.loadError, isNull);
      vm.dispose();
    });

    test('init() loads the recommendation and stops loading', () async {
      storage['userId'] = '42';
      final service = FakeRecommendationService()..response = _sampleResponse();
      final vm = RecommendationsViewModel(recommendationService: service);

      await vm.init();

      expect(service.lastUserId, 42);
      expect(vm.isLoading, isFalse);
      expect(vm.loadError, isNull);
      expect(vm.recommendation?.buildingName, 'Edificio Central');
      expect(vm.recommendation?.tables, hasLength(1));
      vm.dispose();
    });

    test('refresh() sets loadError when the service throws', () async {
      storage['userId'] = '42';
      final service = FakeRecommendationService()
        ..error = Exception('server down');
      final vm = RecommendationsViewModel(recommendationService: service);

      await vm.refresh();

      expect(vm.isLoading, isFalse);
      expect(vm.loadError, contains('server down'));
      expect(vm.recommendation, isNull);
      vm.dispose();
    });

    test('refresh() reports an error when there is no user session', () async {
      final service = FakeRecommendationService()..response = _sampleResponse();
      final vm = RecommendationsViewModel(recommendationService: service);

      await vm.refresh();

      expect(service.calls, 0);
      expect(vm.isLoading, isFalse);
      expect(vm.loadError, contains('No user session found'));
      vm.dispose();
    });

    test('refresh() clears the previous error and dispose() does not fail',
        () async {
      storage['userId'] = '42';
      final service = FakeRecommendationService()..error = Exception('boom');
      final vm = RecommendationsViewModel(recommendationService: service);
      await vm.refresh();
      expect(vm.loadError, isNotNull);

      service
        ..error = null
        ..response = _sampleResponse();
      await vm.refresh();

      expect(vm.loadError, isNull);
      expect(vm.recommendation, isNotNull);
      expect(vm.isLoading, isFalse);
      expect(vm.dispose, returnsNormally);
    });

    test('cache then network: the saved answer stays when the network fails',
        () async {
      storage['userId'] = '42';
      await RecommendationsHiveStore().save(42, _sampleResponse());
      final service = FakeRecommendationService()..error = Exception('offline');
      final vm = RecommendationsViewModel(recommendationService: service);

      await vm.refresh();

      expect(vm.recommendation?.buildingName, 'Edificio Central');
      expect(vm.loadError, isNull);
      expect(vm.isOffline, isTrue);
      expect(vm.lastUpdated, isNotNull);
      expect(vm.isLoading, isFalse);
      vm.dispose();
    });
  });
}
