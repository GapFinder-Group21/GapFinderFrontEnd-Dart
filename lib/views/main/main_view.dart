import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/services/chat_inbox_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_reminder_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/friends_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/main/main_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/open_tables_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/recommendations/recommendations_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/schedule/schedule_view_model.dart';
import 'package:gapfinderfrontend_dart/views/friends/friends_view.dart';
import 'package:gapfinderfrontend_dart/views/match/match_view.dart';
import 'package:gapfinderfrontend_dart/views/open_tables/open_tables_view.dart';
import 'package:gapfinderfrontend_dart/views/recommendations/recommendations_view.dart';
import 'package:gapfinderfrontend_dart/views/schedule/schedule_view.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/bottom_nav.dart';
import 'package:gapfinderfrontend_dart/core/perf/perf_log.dart';

/// Home screen with the bottom navigation bar (Schedule, Friends, Match, Open Tables, Suggestions).
/// It also checks the notifications to show match invitations.
/// Each tab and its ViewModel are created the first time the user opens that tab.
class MainView extends StatelessWidget {
  const MainView({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => MainViewModel()..init()),
        ChangeNotifierProvider(create: (_) => ScheduleViewModel()..init()),
        ChangeNotifierProvider(create: (_) => FriendsViewModel()..init()),
        ChangeNotifierProvider(create: (_) => MatchViewModel()..init()),
        ChangeNotifierProvider(create: (_) => OpenTablesViewModel()..init()),
        ChangeNotifierProvider(create: (_) => RecommendationsViewModel()..init()),
        // New chat messages: notifications and unread counters (runs while the main screen is open)
        Provider<ChatInboxService>(
          // Nobody reads this provider, so without lazy: false it would never be created and never start
          lazy: false,
          create: (_) {
            final inbox = ChatInboxService.instance;
            inbox.start();
            // Android 13+ / iOS: asks the notification permission (one time); without it nothing is shown
            GapReminderService().requestPermission().catchError((Object e) => false);
            return inbox;
          },
          dispose: (_, inbox) => inbox.stop(),
        ),
      ],
      child: const MainTabs(),
    );
  }
}

// The five tab screens, in the order of the bottom bar
const _tabViews = <Widget>[
  ScheduleView(),
  FriendsView(),
  MatchView(),
  OpenTablesView(),
  RecommendationsView(),
];

// Public only so a test can pass light tabs instead of the real screens
@visibleForTesting
class MainTabs extends StatefulWidget {
  const MainTabs({super.key, this.tabs = _tabViews});

  final List<Widget> tabs;

  @override
  State<MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<MainTabs> with WidgetsBindingObserver {
  StreamSubscription<MatchInvitationEvent>? _eventsSub;
  bool _wasInBackground = false;
  // Micro-optimización (lazy tabs): a tab and its ViewModel are built only the first time it is opened
  final Set<int> _visited = {};

  @override
  // Open the invitation screen for each new match request
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Image cache after the first frame of Main (only with PERF_LOGS)
    if (PerfLog.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) => PerfImages.logCache('after Main'));
    }
    final vm = context.read<MainViewModel>();
    vm.registerAppOpen(); // first open
    _eventsSub = vm.events.listen((event) async {
      if (!mounted) return;
      // The route returns true only when the invitation was answered
      final answered = await Navigator.pushNamed<Object?>(context, AppRoutes.matchInvitation, arguments: event.matchId);
      vm.onInvitationClosed(event, answered: answered == true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventsSub?.cancel();
    super.dispose();
  }

  @override
  // In the background the invitation poller stops. Every time the user comes back to the app: resume it,
  // register the open and re-schedule today's reminders.
  // Only after the app was really in the background (not after a permission dialog).
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasInBackground = true;
      context.read<MainViewModel>().pausePolling();
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      context.read<MainViewModel>().resumePolling();
      context.read<MainViewModel>().registerAppOpen();
      context.read<ScheduleViewModel>().scheduleReminders();
    }
  }

  // Switch tab and reload it, like every time the user comes back to a tab
  // (the Open Tables tab is not reloaded, it listens to the GPS instead)
  // The first time a tab opens it is not reloaded: its ViewModel is created now and init() already loads it
  void _onTabChanged(String tabId) {
    final newIndex = context.read<MainViewModel>().selectTab(tabId);
    final firstOpen = newIndex != null && !_visited.contains(newIndex);
    switch (newIndex) {
      case MainViewModel.scheduleTab:
        if (!firstOpen) context.read<ScheduleViewModel>().refresh();
      case MainViewModel.friendsTab:
        if (!firstOpen) context.read<FriendsViewModel>().refresh();
      case MainViewModel.matchTab:
        if (!firstOpen) context.read<MatchViewModel>().refresh();
        // Image cache once the Match tab is on screen (only with PERF_LOGS, logged once)
        if (PerfLog.enabled) {
          WidgetsBinding.instance.addPostFrameCallback((_) => PerfImages.logCache('after Match'));
        }
      case MainViewModel.suggestionsTab:
        if (!firstOpen) context.read<RecommendationsViewModel>().refresh();
      default:
        break;
    }
  }

  @override
  // IndexedStack keeps the opened tabs alive, so switching back to them does not rebuild them
  Widget build(BuildContext context) {
    final vm = context.watch<MainViewModel>();
    // Covers the first tab, the one restored from the last session and the ones opened from a reminder
    _visited.add(vm.selectedIndex);

    return Scaffold(
      // No global offline banner here: each tab shows its own offline notice
      body: IndexedStack(
        index: vm.selectedIndex,
        children: [
          for (var i = 0; i < widget.tabs.length; i++)
            // A tab that was never opened is an empty box that reads no ViewModel
            _visited.contains(i) ? widget.tabs[i] : const SizedBox.shrink(),
        ],
      ),
      // The Friends icon shows how many chat messages are unread
      bottomNavigationBar: ListenableBuilder(
        listenable: ChatInboxService.instance,
        builder: (context, _) => BottomNav(
          activeTab: vm.activeTabId,
          onTab: _onTabChanged,
          friendsBadge: ChatInboxService.instance.totalUnread,
        ),
      ),
    );
  }
}
