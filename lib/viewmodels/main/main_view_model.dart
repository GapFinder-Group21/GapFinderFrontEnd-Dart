import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/models/app_notification.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/notification_type_enum.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/services/notification_service.dart';

// Event: a new match request arrived and its invitation must be shown
class MatchInvitationEvent {
  final int matchId;
  final int notificationId;
  MatchInvitationEvent(this.matchId, this.notificationId);
}

// Home screen: selected tab and the poller of match invitations
class MainViewModel extends ChangeNotifier {
  final NotificationService _notificationService;
  final MatchService _matchService;

  MainViewModel({NotificationService? notificationService, MatchService? matchService})
      : _notificationService = notificationService ?? NotificationService(),
        _matchService = matchService ?? MatchService();

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

  final _events = StreamController<MatchInvitationEvent>.broadcast();
  int _selectedIndex = scheduleTab;
  Timer? _notificationTimer;
  final Set<int> _handledMatchRequests = {};
  bool _checking = false;
  bool _invitationOpen = false;
  int? _userId;
  bool _disposed = false;

  Stream<MatchInvitationEvent> get events => _events.stream;
  int get selectedIndex => _selectedIndex;
  String get activeTabId => _indexMap[_selectedIndex]!;

  // Switch tab when the user taps the bottom bar; returns the new index if it changed
  int? selectTab(String tabId) {
    final index = _navMap[tabId] ?? 0;
    final changed = index != _selectedIndex;
    _selectedIndex = index;
    _notify();
    return changed ? index : null;
  }

  // The backend creates a MATCH_PROPOSED notification when someone sends you a match.
  // Check the unread notifications now and then every 10 seconds
  void init() {
    _checkNotifications();
    _notificationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkNotifications();
    });
  }

  // Sends one event per new match request - GET /api/notifications/user/{userId}/unread
  Future<void> _checkNotifications() async {
    if (_checking || _invitationOpen) return;
    _checking = true;

    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return;
      _userId = userId;

      final unread = await _notificationService.getUnreadByUser(userId);
      final proposals = unread
          .where((n) =>
              n.type == NotificationTypeEnum.MATCH_PROPOSED &&
              n.relatedEntityId != null &&
              !_handledMatchRequests.contains(n.relatedEntityId!))
          .toList()
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

      for (final AppNotification n in proposals) {
        final matchId = n.relatedEntityId!;
        _handledMatchRequests.add(matchId);

        // If the match is no longer pending (expired or cancelled), just mark it as read
        final match = await _matchService.getById(matchId);
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
    } finally {
      _checking = false;
    }
  }

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
    _events.close();
    super.dispose();
  }
}
