import 'package:flutter/material.dart';
import 'dart:async';
import '../widgets/common/bottom_nav.dart';
import '../core/token_storage.dart';
import '../services/notification_service.dart';
import '../services/match_service.dart';
import '../models/app_notification.dart';
import '../models/match_status_enum.dart';
import '../models/notification_type_enum.dart';
import 'schedule/schedule_screen.dart';
import 'friends/friends_screen.dart';
import 'match/match_screen.dart';
import 'open_tables/map_screen.dart';
import 'recommendations/recommendations_screen.dart';

/// Home screen with the bottom navigation bar (Schedule, Friends, Match, Open Tables, Suggestions).
/// It also checks the notifications to show match invitations.
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 0;
  Timer? _notificationTimer;
  final _notificationService = NotificationService();
  final _matchService = MatchService();
  final Set<int> _handledMatchRequests = {};
  bool _checking = false;
  bool _invitationOpen = false;

  @override
  // Start checking notifications when the home screen opens
  void initState() {
    super.initState();
    _startNotificationPoller();
  }

  @override
  // Stop the timer when leaving the screen
  void dispose() {
    _notificationTimer?.cancel();
    super.dispose();
  }

  // The backend creates a MATCH_PROPOSED notification when someone sends you a match.
  // Check the unread notifications now and then every 10 seconds
  void _startNotificationPoller() {
    _checkNotifications();
    _notificationTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _checkNotifications();
    });
  }

  // Opens the invitation screen for each new match request - GET /api/notifications/user/{userId}/unread
  Future<void> _checkNotifications() async {
    if (_checking || _invitationOpen) return;
    _checking = true;

    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return;

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

        if (!mounted) return;
        _invitationOpen = true;
        await Navigator.pushNamed(context, '/match-invitation', arguments: matchId);
        _invitationOpen = false;
        _markAsRead(n.id, userId);
        break; // una invitación a la vez; las demás salen en la siguiente revisión
      }
    } catch (e) {
      debugPrint('⚠️ POLLER ERROR: $e');
    } finally {
      _checking = false;
    }
  }

  // Marks a notification as read - PUT /api/notifications/{notificationId}/read
  Future<void> _markAsRead(int notificationId, int userId) async {
    try {
      await _notificationService.markAsRead(notificationId, userId);
    } catch (e) {
      debugPrint('Error marking read: $e');
    }
  }

  final Map<String, int> _navMap = {
    'schedule': 0,
    'friends': 1,
    'match': 2,
    'map': 3,
    'suggest': 4,
  };

  final Map<int, String> _indexMap = {
    0: 'schedule',
    1: 'friends',
    2: 'match',
    3: 'map',
    4: 'suggest',
  };

  // Switch tab when the user taps the bottom bar
  void _onTabChanged(String tabId) {
    setState(() {
      _selectedIndex = _navMap[tabId] ?? 0;
    });
  }

  @override
  // IndexedStack keeps every tab alive, so switching tabs does not reload them
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          ScheduleScreen(isActive: _selectedIndex == 0),
          FriendsScreen(isActive: _selectedIndex == 1),
          MatchMainScreen(isActive: _selectedIndex == 2),
          const MapScreen(),
          RecommendationsScreen(isActive: _selectedIndex == 4),
        ],
      ),
      bottomNavigationBar: BottomNav(
        activeTab: _indexMap[_selectedIndex]!,
        onTab: _onTabChanged,
      ),
    );
  }
}
