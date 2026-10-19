import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/hive_store.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_handlers.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_theme.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/navigation/navigator_key.dart';
import 'package:gapfinderfrontend_dart/navigation/session_gate.dart';
import 'package:gapfinderfrontend_dart/viewmodels/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initInfrastructure();
  runApp(const MyApp());
}

// Local storage, connectivity and the outbox. If something fails the app still opens (online only).
Future<void> _initInfrastructure() async {
  try {
    await HiveStore.init();
    await AppDatabase.instance.database;
    await ConnectivityService.instance.init(); // the first connection check runs in the background
    registerOutboxHandlers();
    await OutboxService.instance.init(); // sending the pending actions is not awaited
  } catch (e) {
    debugPrint('Error starting the local storage: $e');
  }
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
