import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/friends/friends_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/main/main_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/open_tables_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/recommendations/recommendations_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/schedule/schedule_view_model.dart';
import 'package:gapfinderfrontend_dart/views/main/main_view.dart';

import '../viewmodels/noop_local_cache.dart';

class _Online implements ConnectivityService {
  @override
  bool get isOnline => true;
  @override
  Stream<bool> get onStatusChange => const Stream<bool>.empty();
  @override
  Future<bool> checkNow() async => true;
  @override
  Future<void> init() async {}
  @override
  Future<void> dispose() async {}
}

// Home view model without the notification poller: only the tab selection is real
class _Main extends MainViewModel {
  _Main() : super(connectivity: _Online(), localCache: NoopLocalCache());

  @override
  void init() {}

  @override
  void registerAppOpen() {}
}

// Each tab ViewModel writes "<tab> init" when it is created and "<tab> refresh" when it is reloaded
class _Schedule extends ScheduleViewModel {
  _Schedule(this.log);
  final List<String> log;

  @override
  Future<void> init() async => log.add('Schedule init');
  @override
  Future<void> refresh() async => log.add('Schedule refresh');
}

class _Friends extends FriendsViewModel {
  _Friends(this.log) : super(connectivity: _Online(), localCache: NoopLocalCache());
  final List<String> log;

  @override
  Future<void> init() async => log.add('Friends init');
  @override
  Future<void> refresh({bool silent = false}) async => log.add('Friends refresh');
}

class _Match extends MatchViewModel {
  _Match(this.log) : super(connectivity: _Online(), localCache: NoopLocalCache());
  final List<String> log;

  @override
  Future<void> init() async => log.add('Match init');
  @override
  Future<void> refresh() async => log.add('Match refresh');
}

class _OpenTables extends OpenTablesViewModel {
  _OpenTables(this.log);
  final List<String> log;

  @override
  Future<void> init() async => log.add('OpenTables init');
  @override
  Future<void> refresh() async => log.add('OpenTables refresh');
}

class _Recommendations extends RecommendationsViewModel {
  _Recommendations(this.log);
  final List<String> log;

  @override
  Future<void> init() async => log.add('Recommendations init');
  @override
  Future<void> refresh() async => log.add('Recommendations refresh');
}

// A light tab: like the real screens, it reads its ViewModel when it is built
Widget _tab<T extends ChangeNotifier>(String name) => Builder(builder: (context) {
      context.watch<T>();
      return Text('tab $name');
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> log;
  late _Main mainVm;

  setUp(() {
    // The fonts of the app come from Google Fonts: in a test there is no network to download them
    GoogleFonts.config.allowRuntimeFetching = false;
    log = [];
    mainVm = _Main();
  });

  // Same providers as MainView (lazy: a ViewModel exists only after something reads it)
  Future<void> openHome(WidgetTester tester) async {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exception.toString().contains('GoogleFonts')) return;
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      MaterialApp(
        home: MultiProvider(
          providers: [
            ChangeNotifierProvider<MainViewModel>.value(value: mainVm),
            ChangeNotifierProvider<ScheduleViewModel>(create: (_) => _Schedule(log)..init()),
            ChangeNotifierProvider<FriendsViewModel>(create: (_) => _Friends(log)..init()),
            ChangeNotifierProvider<MatchViewModel>(create: (_) => _Match(log)..init()),
            ChangeNotifierProvider<OpenTablesViewModel>(create: (_) => _OpenTables(log)..init()),
            ChangeNotifierProvider<RecommendationsViewModel>(create: (_) => _Recommendations(log)..init()),
          ],
          child: MainTabs(
            tabs: [
              _tab<ScheduleViewModel>('Schedule'),
              _tab<FriendsViewModel>('Friends'),
              _tab<MatchViewModel>('Match'),
              _tab<OpenTablesViewModel>('OpenTables'),
              _tab<RecommendationsViewModel>('Recommendations'),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> tapNav(WidgetTester tester, Finder item) async {
    await tester.tap(item);
    await tester.pump();
    await tester.pump();
  }

  // The match button in the middle is the only image of the screen
  final friendsItem = find.text('Friends');
  final scheduleItem = find.text('Schedule');
  final matchItem = find.byType(Image);
  final openTablesItem = find.text('Open Tables');
  final suggestItem = find.text('Suggest');

  testWidgets('at start only the selected tab is built and its ViewModel is created', (tester) async {
    await openHome(tester);

    expect(log, ['Schedule init']);
    expect(find.text('tab Schedule'), findsOneWidget);
    expect(find.text('tab Friends'), findsNothing);
    expect(find.text('tab Match'), findsNothing);
    expect(find.text('tab OpenTables'), findsNothing);
    expect(find.text('tab Recommendations'), findsNothing);
  });

  testWidgets('the first time a tab is opened it is built once, without a second load', (tester) async {
    await openHome(tester);

    await tapNav(tester, friendsItem);

    // init() already loads the tab: no refresh() on top of it
    expect(log, ['Schedule init', 'Friends init']);
    expect(find.text('tab Friends'), findsOneWidget);
    expect(find.text('tab Match'), findsNothing);
  });

  testWidgets('every tab loads once in its first opening', (tester) async {
    await openHome(tester);

    await tapNav(tester, friendsItem);
    await tapNav(tester, matchItem);
    await tapNav(tester, openTablesItem);
    await tapNav(tester, suggestItem);

    expect(log, [
      'Schedule init',
      'Friends init',
      'Match init',
      'OpenTables init',
      'Recommendations init',
    ]);
  });

  testWidgets('coming back to an opened tab reloads it and does not build it again', (tester) async {
    await openHome(tester);

    await tapNav(tester, friendsItem);
    await tapNav(tester, scheduleItem);
    await tapNav(tester, friendsItem);

    expect(log, ['Schedule init', 'Friends init', 'Schedule refresh', 'Friends refresh']);
    // Opened tabs stay alive: they are still in the tree while another tab is selected
    expect(find.text('tab Friends', skipOffstage: false), findsOneWidget);
  });

  testWidgets('the Open Tables tab is never reloaded when the user comes back', (tester) async {
    await openHome(tester);

    await tapNav(tester, openTablesItem);
    await tapNav(tester, scheduleItem);
    await tapNav(tester, openTablesItem);

    expect(log.where((e) => e.startsWith('OpenTables')), ['OpenTables init']);
  });

  testWidgets('a tab opened from outside the bar (reminder tap, last session) is built too', (tester) async {
    await openHome(tester);

    // The same call the view model makes when a reminder asks for the Open Tables tab
    mainVm.selectTab('map');
    await tester.pump();

    expect(log, ['Schedule init', 'OpenTables init']);
    expect(find.text('tab OpenTables'), findsOneWidget);
  });
}
