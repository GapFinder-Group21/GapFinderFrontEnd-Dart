import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
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
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';

/// Home screen with the bottom navigation bar (Schedule, Friends, Match, Open Tables, Suggestions).
/// It also checks the notifications to show match invitations.
/// It creates the ViewModel of every tab.
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
      ],
      child: const _MainTabs(),
    );
  }
}

class _MainTabs extends StatefulWidget {
  const _MainTabs();

  @override
  State<_MainTabs> createState() => _MainTabsState();
}

class _MainTabsState extends State<_MainTabs> with WidgetsBindingObserver {
  StreamSubscription<MatchInvitationEvent>? _eventsSub;
  bool _wasInBackground = false;

  @override
  // Open the invitation screen for each new match request
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final vm = context.read<MainViewModel>();
    vm.registerAppOpen(); // first open
    _eventsSub = vm.events.listen((event) async {
      if (!mounted) return;
      await Navigator.pushNamed(context, AppRoutes.matchInvitation, arguments: event.matchId);
      vm.onInvitationClosed(event.notificationId);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _eventsSub?.cancel();
    super.dispose();
  }

  @override
  // Every time the user comes back to the app: register the open and re-schedule today's reminders.
  // Only after the app was really in the background (not after a permission dialog).
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _wasInBackground = true;
    } else if (state == AppLifecycleState.resumed && _wasInBackground) {
      _wasInBackground = false;
      context.read<MainViewModel>().registerAppOpen();
      context.read<ScheduleViewModel>().scheduleReminders();
    }
  }

  // Switch tab and reload it, like every time the user comes back to a tab
  // (the Open Tables tab is not reloaded, it listens to the GPS instead)
  void _onTabChanged(String tabId) {
    final newIndex = context.read<MainViewModel>().selectTab(tabId);
    switch (newIndex) {
      case MainViewModel.scheduleTab:
        context.read<ScheduleViewModel>().refresh();
      case MainViewModel.friendsTab:
        context.read<FriendsViewModel>().refresh();
      case MainViewModel.matchTab:
        context.read<MatchViewModel>().refresh();
      case MainViewModel.suggestionsTab:
        context.read<RecommendationsViewModel>().refresh();
      default:
        break;
    }
  }

  @override
  // IndexedStack keeps every tab alive, so switching tabs does not reload them
  Widget build(BuildContext context) {
    final vm = context.watch<MainViewModel>();

    final count = vm.unreadCount;
    final saved = count == 1 ? '1 notificación guardada' : '$count notificaciones guardadas';

    return Scaffold(
      body: Column(
        children: [
          // Without connection: the tabs still work, the invitations check is paused
          // (always one child here, so the tabs below keep their position and their state)
          vm.isOffline
              ? SafeArea(
                  bottom: false,
                  child: OfflineBanner(
                    message: 'Sin conexión · navegación local activa · $saved',
                    lastUpdated: vm.lastUpdated,
                  ),
                )
              : const SizedBox.shrink(),
          Expanded(
            // The banner already covers the status bar, so the tabs must not add it again.
            // (Same widget types in both cases, so the tabs keep their state)
            child: MediaQuery.removePadding(
              context: context,
              removeTop: vm.isOffline,
              child: IndexedStack(
                index: vm.selectedIndex,
                children: const [
                  ScheduleView(),
                  FriendsView(),
                  MatchView(),
                  OpenTablesView(),
                  RecommendationsView(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNav(
        activeTab: vm.activeTabId,
        onTab: _onTabChanged,
      ),
    );
  }
}
