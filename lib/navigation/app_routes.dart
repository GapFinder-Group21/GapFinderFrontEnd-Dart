import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/google_calendar_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/google_connect_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/interests_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/location_permission_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/login_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/register_view_model.dart';
import 'package:gapfinderfrontend_dart/views/auth/google_calendar_view.dart';
import 'package:gapfinderfrontend_dart/views/auth/google_connect_view.dart';
import 'package:gapfinderfrontend_dart/views/auth/interests_view.dart';
import 'package:gapfinderfrontend_dart/views/auth/location_permission_view.dart';
import 'package:gapfinderfrontend_dart/views/auth/login_view.dart';
import 'package:gapfinderfrontend_dart/views/auth/register_view.dart';
import 'package:gapfinderfrontend_dart/views/auth/schedule_setup_view.dart';
import 'package:gapfinderfrontend_dart/views/welcome/welcome_view.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_found_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_invitation_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/its_a_match_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/searching_match_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/waiting_view_model.dart';
import 'package:gapfinderfrontend_dart/views/match/its_a_match_view.dart';
import 'package:gapfinderfrontend_dart/views/match/match_found_view.dart';
import 'package:gapfinderfrontend_dart/views/match/match_invitation_view.dart';
import 'package:gapfinderfrontend_dart/views/match/searching_match_view.dart';
import 'package:gapfinderfrontend_dart/views/match/waiting_view.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/create_open_table_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/my_open_tables_view_model.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/open_table_detail_view_model.dart';
import 'package:gapfinderfrontend_dart/views/open_tables/create_open_table_view.dart';
import 'package:gapfinderfrontend_dart/views/open_tables/my_open_tables_view.dart';
import 'package:gapfinderfrontend_dart/views/open_tables/open_table_detail_view.dart';
import 'package:gapfinderfrontend_dart/views/main/main_view.dart';
import 'package:gapfinderfrontend_dart/viewmodels/schedule/schedule_view_model.dart';
import 'package:gapfinderfrontend_dart/views/schedule/schedule_view.dart';

// Route names of the app and the builder of each route (each View gets its ViewModel here)
class AppRoutes {
  static const welcome = '/welcome';
  static const register = '/register';
  static const login = '/login';
  static const locationPermission = '/location-permission';
  static const home = '/home';
  static const interests = '/interests';
  static const schedule = '/schedule';
  static const scheduleSetup = '/schedule-setup';
  static const googleCalendar = '/google-calendar';
  static const googleConnect = '/google-connect';
  static const searchingMatch = '/searching-match';
  static const matchFound = '/match-found';
  static const waitingMatch = '/waiting-match';
  static const itsAMatch = '/its-a-match';
  static const matchInvitation = '/match-invitation';
  static const createOpenTable = '/create-open-table';
  static const myOpenTables = '/my-open-tables';
  static const openTableDetail = '/open-table-detail';

  static Map<String, WidgetBuilder> get routes => {
        welcome: (context) => const WelcomeView(),
        register: (context) => withViewModel(() => RegisterViewModel(), const RegisterView()),
        login: (context) => withViewModel(() => LoginViewModel(), const LoginView()),
        locationPermission: (context) =>
            withViewModel(() => LocationPermissionViewModel()..init(), const LocationPermissionView()),
        home: (context) => const MainView(),
        interests: (context) => withViewModel(() => InterestsViewModel()..init(), const InterestsView()),
        schedule: (context) => withViewModel(() => ScheduleViewModel()..init(), const ScheduleView()),
        scheduleSetup: (context) => const ScheduleSetupView(),
        googleCalendar: (context) =>
            withViewModel(() => GoogleCalendarViewModel()..init(), const GoogleCalendarView()),
        googleConnect: (context) => withViewModel(() => GoogleConnectViewModel(), const GoogleConnectView()),
        searchingMatch: (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return withViewModel(
            () => SearchingMatchViewModel(args['userId'], args['mode']),
            const SearchingMatchView(),
          );
        },
        matchFound: (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return withViewModel(
            () => MatchFoundViewModel(
              userId: args['userId'],
              currentGapId: args['currentGapId'],
              candidate: args['candidate'] as MatchCandidate,
              selectedMode: args['selectedMode'] as MatchModeEnum,
            ),
            const MatchFoundView(),
          );
        },
        waitingMatch: (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return withViewModel(
            () => WaitingViewModel(
              matchId: args['matchId'],
              requesterId: args['requesterId'],
              candidateUser: args['candidateUser'],
            )..init(),
            const WaitingView(),
          );
        },
        itsAMatch: (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return withViewModel(
            () => ItsAMatchViewModel(args['matchId'])..init(),
            ItsAMatchView(
              matchId: args['matchId'],
              candidateUser: args['candidateUser'],
              suggestedActivity: args['suggestedActivity'],
              chosenActivity: args['chosenActivity'],
            ),
          );
        },
        matchInvitation: (context) {
          final matchId = ModalRoute.of(context)!.settings.arguments as int;
          return withViewModel(() => MatchInvitationViewModel(matchId), const MatchInvitationView());
        },
        createOpenTable: (context) =>
            withViewModel(() => CreateOpenTableViewModel()..init(), const CreateOpenTableView()),
        myOpenTables: (context) => withViewModel(() => MyOpenTablesViewModel()..init(), const MyOpenTablesView()),
        openTableDetail: (context) {
          final openTableId = ModalRoute.of(context)!.settings.arguments as int;
          return withViewModel(
            () => OpenTableDetailViewModel(openTableId)..init(),
            const OpenTableDetailView(),
          );
        },
      };

  // Wraps a View with its own ViewModel
  static Widget withViewModel<T extends ChangeNotifier>(T Function() create, Widget view) {
    return ChangeNotifierProvider<T>(create: (_) => create(), child: view);
  }
}
