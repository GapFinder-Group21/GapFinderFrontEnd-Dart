import 'package:flutter/material.dart';

// Global navigator, used by ApiClient to send the user to /welcome when the session expires
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// Global messenger, used to show a SnackBar on whatever screen is open (e.g. a queued action was sent)
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
