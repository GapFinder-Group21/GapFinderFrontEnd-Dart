import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/views/main/main_view.dart';
import 'package:gapfinderfrontend_dart/views/welcome/welcome_view.dart';
import 'package:gapfinderfrontend_dart/viewmodels/session/session_view_model.dart';

// Opens /home if there is a saved session (or the onboarding screen where the user left it);
// if the token expired, ApiClient refreshes it and, if the refresh also fails, sends the user to /welcome
class SessionGateView extends StatelessWidget {
  const SessionGateView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SessionViewModel()..init(),
      child: Consumer<SessionViewModel>(
        builder: (context, vm, _) {
          final hasSession = vm.hasSession;
          if (hasSession == null) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!hasSession) return const WelcomeView();

          // The app was closed in the middle of the onboarding: it goes on at the same screen
          final resumeRoute = vm.resumeRoute;
          final builder = resumeRoute == null ? null : AppRoutes.routes[resumeRoute];
          return builder == null ? const MainView() : builder(context);
        },
      ),
    );
  }
}
