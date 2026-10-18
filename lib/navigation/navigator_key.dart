import 'package:flutter/material.dart';

// Global navigator, used by ApiClient to send the user to /welcome when the session expires
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
