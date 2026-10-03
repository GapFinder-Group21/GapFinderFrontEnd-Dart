import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/screens/auth/google_connect_screen.dart';
import 'package:gapfinderfrontend_dart/screens/welcome/welcome_screen.dart';
import 'package:gapfinderfrontend_dart/screens/auth/register_screen.dart';
import 'package:gapfinderfrontend_dart/screens/auth/login_screen.dart';
import 'package:gapfinderfrontend_dart/screens/auth/location_permission_screen.dart';
import 'package:gapfinderfrontend_dart/screens/auth/schedule_setup_screen.dart';
import 'package:gapfinderfrontend_dart/screens/auth/interests_screen.dart';
import 'package:gapfinderfrontend_dart/screens/auth/google_calendar_screen.dart';
import 'package:gapfinderfrontend_dart/screens/main_screen.dart';
import 'package:gapfinderfrontend_dart/screens/schedule/schedule_screen.dart';
import 'package:gapfinderfrontend_dart/screens/match/searching_match_screen.dart';
import 'package:gapfinderfrontend_dart/screens/match/match_found_screen.dart';
import 'package:gapfinderfrontend_dart/screens/match/waiting_screen.dart';
import 'package:gapfinderfrontend_dart/screens/match/its_a_match_screen.dart';
import 'package:gapfinderfrontend_dart/screens/match/match_invitation_screen.dart';
import 'package:gapfinderfrontend_dart/screens/open_tables/create_open_table_screen.dart';
import 'package:gapfinderfrontend_dart/screens/open_tables/my_open_tables_screen.dart';
import 'package:gapfinderfrontend_dart/screens/open_tables/open_table_detail_screen.dart';
import 'package:gapfinderfrontend_dart/screens/schedule/gap_detail_screen.dart';
import 'core/token_storage.dart';
import 'models/match_candidate.dart';
import 'models/match_mode_enum.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GAP FINDER',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      home: const _SessionGate(),
      routes: {
        '/welcome': (context) => const WelcomeScreen(),
        '/register': (context) => const RegisterScreen(),
        '/login': (context) => const LoginScreen(),
        '/location-permission': (context) => const LocationPermissionScreen(),
        '/home': (context) => const MainScreen(),
        '/interests': (context) => const InterestsScreen(),
        '/schedule': (context) => const ScheduleScreen(),
        '/schedule-setup': (context) => const ScheduleSetupScreen(),
        '/google-calendar': (context) => const GoogleCalendarScreen(),
        '/google-connect': (context) => const GoogleConnectScreen(),
        '/searching-match': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return SearchingMatchScreen(
            userId: args['userId'],
            mode: args['mode'],
          );
        },
        '/match-found': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return MatchFoundScreen(
            userId: args['userId'],
            currentGapId: args['currentGapId'],
            candidate: args['candidate'] as MatchCandidate,
            selectedMode: args['selectedMode'] as MatchModeEnum,
          );
        },
        '/waiting-match': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return WaitingScreen(
            matchId: args['matchId'],
            requesterId: args['requesterId'],
            candidateUser: args['candidateUser'],
          );
        },
        '/its-a-match': (context) {
          final args = ModalRoute.of(context)!.settings.arguments as Map<String, dynamic>;
          return ItsAMatchScreen(
            matchId: args['matchId'],
            candidateUser: args['candidateUser'],
            suggestedActivity: args['suggestedActivity'],
            chosenActivity: args['chosenActivity'],
          );
        },
        '/match-invitation': (context) {
          final matchId = ModalRoute.of(context)!.settings.arguments as int;
          return MatchInvitationScreen(matchId: matchId);
        },
        '/create-open-table': (context) => const CreateOpenTableScreen(),
        '/my-open-tables': (context) => const MyOpenTablesScreen(),
        '/open-table-detail': (context) {
          final openTableId = ModalRoute.of(context)!.settings.arguments as int;
          return OpenTableDetailScreen(openTableId: openTableId);
        },
        '/gap-detail': (context) {
          final gapId = ModalRoute.of(context)!.settings.arguments as int;
          return GapDetailScreen(gapId: gapId);
        },
      },
    );
  }
}

// Abre /home si hay sesión guardada; si el token venció, ApiClient lo refresca
// y, si el refresh también falla, manda a /welcome
class _SessionGate extends StatelessWidget {
  const _SessionGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: TokenStorage.hasSession(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        return snapshot.data! ? const MainScreen() : const WelcomeScreen();
      },
    );
  }
}
