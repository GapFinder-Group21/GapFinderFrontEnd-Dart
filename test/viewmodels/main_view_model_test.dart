import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/models/app_notification.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/notification_type_enum.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/services/notification_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/main/main_view_model.dart';

import 'noop_local_cache.dart';
import 'secure_storage_mock.dart';

class _OnlineConnectivity implements ConnectivityService {
  final _controller = StreamController<bool>.broadcast();

  @override
  bool get isOnline => true;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  @override
  Future<bool> checkNow() async => true;

  @override
  Future<void> init() async {}

  @override
  Future<void> dispose() async {}
}

class _FakeNotifications extends NotificationService {
  List<AppNotification> unread = [];
  final List<int> markedRead = [];
  // When true the request never answers, like a hung connection
  bool hang = false;
  int calls = 0;

  @override
  Future<List<AppNotification>> getUnreadByUser(int userId) {
    calls++;
    if (hang) return Completer<List<AppNotification>>().future;
    return Future.value(unread);
  }

  @override
  Future<AppNotification> markAsRead(int notificationId, int userId) async {
    markedRead.add(notificationId);
    return unread.firstWhere((n) => n.id == notificationId);
  }
}

class _FakeMatches extends MatchService {
  // Errors thrown by the next calls of getById, in order; then the match is returned
  final List<Object> errors = [];
  MatchStatusEnum status = MatchStatusEnum.PENDING;
  int calls = 0;

  @override
  Future<Match> getById(int id) async {
    calls++;
    if (errors.isNotEmpty) throw errors.removeAt(0);
    final now = DateTime.now();
    return Match(id: id, startTime: now, endTime: now.add(const Duration(minutes: 30)), status: status);
  }
}

AppNotification _proposal(int id, int matchId) => AppNotification(
      id: id,
      type: NotificationTypeEnum.MATCH_PROPOSED,
      message: 'New match',
      relatedEntityId: matchId,
      read: false,
      createdAt: DateTime.now(),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final storage = SecureStorageMock();
  late _FakeNotifications notifications;
  late _FakeMatches matches;
  late MainViewModel vm;

  setUp(() {
    storage.install();
    storage.setUserId(1);
    notifications = _FakeNotifications();
    matches = _FakeMatches();
    vm = MainViewModel(
      notificationService: notifications,
      matchService: matches,
      localCache: NoopLocalCache(),
      connectivity: _OnlineConnectivity(),
    );
  });

  tearDown(() {
    vm.dispose();
    storage.uninstall();
  });

  group('J-4: the invitation poller', () {
    test('a failed getById does not lose the invitation: the next check opens it', () async {
      notifications.unread = [_proposal(10, 77)];
      matches.errors.add(const SocketException('network blip'));
      final opened = <int>[];
      vm.events.listen((e) => opened.add(e.matchId));

      await vm.checkNotificationsNow();
      expect(opened, isEmpty);

      await vm.checkNotificationsNow();
      await Future<void>.delayed(Duration.zero);
      expect(opened, [77]);
    });

    test('a server error (5xx) is retried on the next check too', () async {
      notifications.unread = [_proposal(10, 77)];
      matches.errors.add(Exception('Error getting match: 500'));
      final opened = <int>[];
      vm.events.listen((e) => opened.add(e.matchId));

      await vm.checkNotificationsNow();
      await vm.checkNotificationsNow();
      await Future<void>.delayed(Duration.zero);

      expect(opened, [77]);
      expect(matches.calls, 2);
    });

    test('a match that does not exist anymore (404) is marked as read and not checked again', () async {
      notifications.unread = [_proposal(10, 77)];
      matches.errors.add(MatchNotFoundException(77));

      await vm.checkNotificationsNow();
      await Future<void>.delayed(Duration.zero);
      expect(notifications.markedRead, [10]);

      await vm.checkNotificationsNow();
      expect(matches.calls, 1);
    });

    test('a request that hangs is cut by the time limit, so the poller keeps working', () async {
      vm.dispose();
      vm = MainViewModel(
        notificationService: notifications,
        matchService: matches,
        localCache: NoopLocalCache(),
        connectivity: _OnlineConnectivity(),
        requestTimeout: const Duration(milliseconds: 50),
      );
      notifications.hang = true;
      await vm.checkNotificationsNow();

      notifications.hang = false;
      await vm.checkNotificationsNow();

      expect(notifications.calls, 2);
    });
  });

  group('J-6: the invitation poller in the background', () {
    test('it does not check while paused and checks at once when resumed', () async {
      vm.pausePolling();
      await vm.checkNotificationsNow();
      expect(notifications.calls, 0);

      vm.resumePolling();
      await Future<void>.delayed(Duration.zero);
      expect(notifications.calls, 1);
    });

    test('resume without a pause does nothing', () async {
      vm.resumePolling();
      await Future<void>.delayed(Duration.zero);
      expect(notifications.calls, 0);
    });
  });
}
