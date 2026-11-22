import 'dart:async';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/chat_message_dao.dart';
import 'package:gapfinderfrontend_dart/models/chat_message.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/chat_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/chat_processing.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/chat_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/current_location_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/theme/theme_controller.dart';

// GPS plugin that counts how many times the location is asked (GPS off: no request to the back)
class _FakeGeolocator extends GeolocatorPlatform {
  int locationChecks = 0;

  @override
  Future<bool> isLocationServiceEnabled() async {
    locationChecks++;
    return false;
  }

  @override
  Stream<ServiceStatus> getServiceStatusStream() => const Stream<ServiceStatus>.empty();
}

class _FakeConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();
  bool online = true;

  void setOnline(bool value) {
    online = value;
    _controller.add(value);
  }

  @override
  bool get isOnline => online;
  @override
  Stream<bool> get onStatusChange => _controller.stream;
  @override
  Future<bool> checkNow() async => online;
  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
}

// Back of the chat that counts the polls
class _FakeChat extends ChatService {
  int polls = 0;

  @override
  Future<String> getConversationBody(int userId, int friendId, {int afterId = 0}) async {
    polls++;
    return '[]';
  }

  @override
  Future<ChatMessage?> send(int receiverId, String content, String clientId) async => null;
}

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  sqfliteFfiInit();

  group('location banner', () {
    late _FakeGeolocator geolocator;

    setUp(() {
      geolocator = _FakeGeolocator();
      GeolocatorPlatform.instance = geolocator;
    });

    test('in the background there is no timer and no location is asked; it comes back on resume', () async {
      final vm = CurrentLocationViewModel(1);
      vm.init();
      await _settle();
      expect(vm.isTimerActive, isTrue);
      expect(geolocator.locationChecks, 1);

      vm.handleAppLifecycle(AppLifecycleState.paused);
      expect(vm.isTimerActive, isFalse);
      await vm.updateLocation(); // the timer or the network coming back would call this
      expect(geolocator.locationChecks, 1);

      vm.handleAppLifecycle(AppLifecycleState.resumed);
      await _settle();
      expect(vm.isTimerActive, isTrue);
      expect(geolocator.locationChecks, 2); // one update at once on resume
      vm.dispose();
    });

    test('hidden then paused stops it only once', () async {
      final vm = CurrentLocationViewModel(1);
      vm.init();
      await _settle();
      vm.handleAppLifecycle(AppLifecycleState.hidden);
      vm.handleAppLifecycle(AppLifecycleState.paused);
      expect(vm.isTimerActive, isFalse);
      vm.handleAppLifecycle(AppLifecycleState.resumed);
      await _settle();
      expect(geolocator.locationChecks, 2);
      vm.dispose();
    });
  });

  group('chat polling', () {
    late Database db;
    late OutboxService outbox;
    late _FakeChat chat;
    late _FakeConnectivity connectivity;
    late ChatViewModel vm;

    setUp(() async {
      ChatViewModel.clearChatCache();
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await AppDatabase.createModuleTables(db);
      outbox = OutboxService.forTesting(
        database: () async => db,
        send: (method, endpoint, body) async => http.Response('{}', 201),
      );
      chat = _FakeChat();
      connectivity = _FakeConnectivity();
      vm = ChatViewModel(
        User(id: 2, name: 'Ana', email: 'ana@gmail.com', career: 'Systems'),
        chatService: chat,
        dao: ChatMessageDao(database: () async => db),
        connectivity: connectivity,
        outbox: outbox,
        readUserId: () async => 1,
        merge: (payload) async => mergeChatMessages(payload),
        pollEvery: const Duration(hours: 1),
      );
      await vm.init();
    });

    tearDown(() async {
      vm.dispose();
      await outbox.dispose();
      await db.close();
    });

    test('in the background it does not poll, even if the network comes back', () async {
      expect(vm.isPolling, isTrue);
      final before = chat.polls;

      vm.handleAppLifecycle(AppLifecycleState.paused);
      expect(vm.isPolling, isFalse);

      connectivity.setOnline(false);
      connectivity.setOnline(true);
      await _settle();
      await vm.fetchNew();

      expect(vm.isPolling, isFalse);
      expect(chat.polls, before);
    });

    test('on resume with connection it fetches once and the polling starts again', () async {
      vm.handleAppLifecycle(AppLifecycleState.paused);
      final before = chat.polls;

      vm.handleAppLifecycle(AppLifecycleState.resumed);
      await _settle();

      expect(chat.polls, before + 1);
      expect(vm.isPolling, isTrue);
    });

    test('on resume without connection it waits for the network', () async {
      vm.handleAppLifecycle(AppLifecycleState.paused);
      connectivity.setOnline(false);
      await _settle();
      final before = chat.polls;

      vm.handleAppLifecycle(AppLifecycleState.resumed);
      await _settle();

      expect(chat.polls, before);
      expect(vm.isPolling, isFalse);
    });
  });

  group('light sensor', () {
    test('readings are ignored in the background and used again after resume', () async {
      final lux = StreamController<int>.broadcast();
      final controller = ThemeController(lightStream: lux.stream, settle: const Duration(milliseconds: 20));

      controller.handleAppLifecycle(AppLifecycleState.paused);
      lux.add(0); // very dark
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.themeMode, ThemeMode.system); // nobody is listening

      controller.handleAppLifecycle(AppLifecycleState.resumed);
      lux.add(0);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(controller.themeMode, ThemeMode.dark);

      controller.dispose();
      await lux.close();
    });

    test('a pending mode change is dropped when the app goes to the background', () async {
      final lux = StreamController<int>.broadcast();
      final controller = ThemeController(lightStream: lux.stream, settle: const Duration(milliseconds: 40));

      lux.add(0);
      await Future<void>.delayed(const Duration(milliseconds: 5));
      controller.handleAppLifecycle(AppLifecycleState.paused);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(controller.themeMode, ThemeMode.system);

      controller.dispose();
      await lux.close();
    });
  });
}
