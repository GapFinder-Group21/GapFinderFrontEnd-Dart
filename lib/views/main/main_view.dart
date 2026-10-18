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

class _MainTabsState extends State<_MainTabs> {
  StreamSubscription<MatchInvitationEvent>? _eventsSub;

  @override
  // Open the invitation screen for each new match request
  void initState() {
    super.initState();
    final vm = context.read<MainViewModel>();
    _eventsSub = vm.events.listen((event) async {
      if (!mounted) return;
      await Navigator.pushNamed(context, AppRoutes.matchInvitation, arguments: event.matchId);
      vm.onInvitationClosed(event.notificationId);
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
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

    return Scaffold(
      body: IndexedStack(
        index: vm.selectedIndex,
        children: const [
          ScheduleView(),
          FriendsView(),
          MatchView(),
          OpenTablesView(),
          RecommendationsView(),
        ],
      ),
      bottomNavigationBar: BottomNav(
        activeTab: vm.activeTabId,
        onTab: _onTabChanged,
      ),
    );
  }
}
