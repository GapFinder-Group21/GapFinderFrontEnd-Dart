import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/app_notification.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/notification_type_enum.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/services/app_session_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_reminder_service.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/services/notification_service.dart';

// Event: a new match request arrived and its invitation must be shown
class MatchInvitationEvent {
  final int matchId;
  final int notificationId;
  MatchInvitationEvent(this.matchId, this.notificationId);
}

// Home screen: selected tab and the poller of match invitations.
// Navigation between tabs is local, so it works without connection. The poller needs the back:
// it pauses without connection (the notifications come from SQLite) and resumes when it is back.
class MainViewModel extends ChangeNotifier {
  final NotificationService _notificationService;
  final MatchService _matchService;
  final AppSessionService _appSessionService;
  final GapReminderService _reminderService;
  final JoelLocalCache _localCache;
  final ConnectivityService _connectivity;
  // Each request of the poller waits at most this long, so a hung request never freezes it
  final Duration requestTimeout;

  MainViewModel({
    NotificationService? notificationService,
    MatchService? matchService,
    AppSessionService? appSessionService,
    GapReminderService? reminderService,
    JoelLocalCache? localCache,
    ConnectivityService? connectivity,
    this.requestTimeout = const Duration(seconds: 10),
  })  : _notificationService = notificationService ?? NotificationService(),
        _matchService = matchService ?? MatchService(),
        _appSessionService = appSessionService ?? AppSessionService(),
        _reminderService = reminderService ?? GapReminderService(),
        _localCache = localCache ?? JoelLocalCache.instance,
        _connectivity = connectivity ?? ConnectivityService.instance;

  static const scheduleTab = 0;
  static const friendsTab = 1;
  static const matchTab = 2;
  static const openTablesTab = 3;
  static const suggestionsTab = 4;

  final Map<String, int> _navMap = {
    'schedule': scheduleTab,
    'friends': friendsTab,
    'match': matchTab,
    'map': openTablesTab,
    'suggest': suggestionsTab,
  };

  final Map<int, String> _indexMap = {
    scheduleTab: 'schedule',
    friendsTab: 'friends',
    matchTab: 'match',
    openTablesTab: 'map',
    suggestionsTab: 'suggest',
  };

  // Estrategia: Stream. A broadcast StreamController sends one event per new match request
  // and the View listens to it to open the invitation screen.
  final _events = StreamController<MatchInvitationEvent>.broadcast();
  int _selectedIndex = scheduleTab;
  Timer? _notificationTimer;
  StreamSubscription<void>? _reminderTapSub;
  StreamSubscription<bool>? _connectivitySub;
  bool _isOffline = false;
  bool _tabTouched = false;
  List<AppNotification> _notifications = [];
  DateTime? _lastUpdated;
  final Set<int> _handledMatchRequests = {};
  bool _checking = false;
  bool _invitationOpen = false;
  int? _userId;
  bool _disposed = false;

  Stream<MatchInvitationEvent> get events => _events.stream;
  int get selectedIndex => _selectedIndex;
  String get activeTabId => _indexMap[_selectedIndex]!;
  bool get isOffline => _isOffline;
  // When the notifications on screen were last updated (the network answer or the saved copy)
  DateTime? get lastUpdated => _lastUpdated;
  // The unread notifications (from the back, or from SQLite when there is no connection)
  List<AppNotification> get notifications => _notifications;
  int get unreadCount => _notifications.where((n) => !n.read).length;

  // Switch tab when the user taps the bottom bar; returns the new index if it changed
  int? selectTab(String tabId) {
    final index = _navMap[tabId] ?? 0;
    final changed = index != _selectedIndex;
    _tabTouched = true;
    _selectedIndex = index;
    if (changed) _localCache.saveMainTab(index);
    _notify();
    return changed ? index : null;
  }

  // The backend creates a MATCH_PROPOSED notification when someone sends you a match.
  // Check the unread notifications now and then every 10 seconds
  // Without connection it does not poll: it shows the saved notifications and waits.
  void init() {
    _isOffline = !_connectivity.isOnline;
    _restoreLastTab();
    _listenReminderTaps();
    _connectivitySub = _connectivity.onStatusChange.listen(_onConnectivityChanged);

    if (_isOffline) {
      _loadSavedNotifications();
    } else {
      _checkNotifications();
      _startPolling();
    }
  }

  // Opens the tab the user had open last time (main_last_tab), unless they already moved
  // or a reminder tap sent them somewhere
  Future<void> _restoreLastTab() async {
    final saved = await _localCache.safeRead('main tab', _localCache.mainTab.get);
    if (saved == null || _tabTouched || _disposed) return;
    if (!_indexMap.containsKey(saved)) return;
    _selectedIndex = saved;
    _notify();
  }

  void _startPolling() {
    _notificationTimer?.cancel();
    _notificationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_isOffline) return;
      _checkNotifications();
    });
  }

  void _stopPolling() {
    _notificationTimer?.cancel();
    _notificationTimer = null;
  }

  // Pauses the poller without connection and resumes it (checking at once) when it is back
  void _onConnectivityChanged(bool online) {
    _isOffline = !online;
    if (online) {
      _checkNotifications();
      _startPolling();
    } else {
      _stopPolling();
      _loadSavedNotifications();
    }
    _notify();
  }

  // Notifications saved in SQLite (the unread ones of the last network answer)
  Future<void> _loadSavedNotifications() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return;
    final saved = await _localCache.safeRead('notifications', () async {
      final list = await _localCache.notifications.getAllForUser(userId);
      final savedAt = await _localCache.notifications.lastSavedAt(userId);
      return (list, savedAt);
    });
    if (saved == null || _disposed) return;
    _notifications = saved.$1;
    _lastUpdated = saved.$2;
    _notify();
  }

  // Registers that the user opened the app - POST /app-sessions/user/{userId}
  // Never blocks the user: it is not awaited and an error only prints
  void registerAppOpen() {
    // Estrategia: Future con handler (.then + .catchError)
    TokenStorage.getUserId().then((userId) {
      if (userId == null) return null;
      return _appSessionService.registerOpen(userId);
    }).catchError((e) {
      debugPrint('Error registering app open: $e');
    });
  }

  // A tap on a gap reminder (even the one that opened the app) goes to the Open Tables tab
  Future<void> _listenReminderTaps() async {
    try {
      await _reminderService.init();
      if (_disposed) return;
      if (_reminderService.takeOpenTablesRequest()) selectTab('map');
      _reminderTapSub = _reminderService.taps.listen((_) {
        _reminderService.takeOpenTablesRequest();
        selectTab('map');
      });
    } catch (e) {
      debugPrint('Error listening to the reminders: $e');
    }
  }

  // Sends one event per new match request - GET /api/notifications/user/{userId}/unread
  Future<void> _checkNotifications() async {
    if (_checking || _invitationOpen || _isOffline) return;
    _checking = true;

    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return;
      _userId = userId;

      final unread = await _notificationService.getUnreadByUser(userId).timeout(requestTimeout);
      // Cached on network response (never blocks the poller)
      _localCache.saveNotifications(userId, unread);
      _notifications = unread;
      _lastUpdated = DateTime.now();
      _notify();
      final proposals = unread
          .where((n) =>
              n.type == NotificationTypeEnum.MATCH_PROPOSED &&
              n.relatedEntityId != null &&
              !_handledMatchRequests.contains(n.relatedEntityId!))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      for (final AppNotification n in proposals) {
        final matchId = n.relatedEntityId!;

        final Match match;
        try {
          match = await _matchService.getById(matchId).timeout(requestTimeout);
        } on MatchNotFoundException {
          // The match does not exist anymore: mark it as read so it is not checked again
          _handledMatchRequests.add(matchId);
          _markAsRead(n.id, userId);
          continue;
        }
        // Only now it counts as handled: if getById failed, the next check tries again
        _handledMatchRequests.add(matchId);

        // If the match is no longer pending (expired or cancelled), just mark it as read
        _localCache.saveInvitationMatch(match); // so the invitation can open without connection
        if (match.status != MatchStatusEnum.PENDING) {
          _markAsRead(n.id, userId);
          continue;
        }

        if (_disposed) return;
        _invitationOpen = true;
        _events.add(MatchInvitationEvent(matchId, n.id));
        break; // una invitación a la vez; las demás salen en la siguiente revisión
      }
    } catch (e) {
      debugPrint('⚠️ POLLER ERROR: $e');
      // The network failed: show what is saved instead of leaving old data
      _loadSavedNotifications();
    } finally {
      _checking = false;
    }
  }

  // Runs one check of the notifications now (for tests)
  @visibleForTesting
  Future<void> checkNotificationsNow() => _checkNotifications();

  // Called by the View when the invitation screen is closed
  void onInvitationClosed(int notificationId) {
    _invitationOpen = false;
    final userId = _userId;
    if (userId != null) _markAsRead(notificationId, userId);
  }

  // Marks a notification as read - PUT /api/notifications/{notificationId}/read
  Future<void> _markAsRead(int notificationId, int userId) async {
    try {
      await _notificationService.markAsRead(notificationId, userId);
    } catch (e) {
      debugPrint('Error marking read: $e');
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  // Stop the timer when leaving the screen
  void dispose() {
    _disposed = true;
    _notificationTimer?.cancel();
    _reminderTapSub?.cancel();
    _connectivitySub?.cancel();
    _events.close();
    super.dispose();
  }
}
