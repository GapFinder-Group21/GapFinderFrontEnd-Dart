import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_theme.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/navigation/navigator_key.dart';
import 'package:gapfinderfrontend_dart/navigation/session_gate.dart';
import 'package:gapfinderfrontend_dart/viewmodels/theme/theme_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  // Listens to the light sensor for the whole life of the app
  final ThemeController _themeController = ThemeController();

  @override
  void dispose() {
    _themeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _themeController,
      builder: (context, _) => MaterialApp(
        title: 'GAP FINDER',
        navigatorKey: navigatorKey,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: _themeController.themeMode,
        home: const SessionGateView(),
        routes: AppRoutes.routes,
      ),
    );
  }
}
