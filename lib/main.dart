import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/navigation/navigator_key.dart';
import 'package:gapfinderfrontend_dart/navigation/session_gate.dart';

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
      home: const SessionGateView(),
      routes: AppRoutes.routes,
    );
  }
}
