import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';

void main() {
  testWidgets('goHome leaves a single home screen and nothing to go back to', (tester) async {
    var homesBuilt = 0;
    final navigatorKey = GlobalKey<NavigatorState>();

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      initialRoute: AppRoutes.home,
      onGenerateRoute: (settings) {
        if (settings.name == AppRoutes.home) {
          return MaterialPageRoute(builder: (_) {
            homesBuilt++;
            return const Scaffold(body: Text('HOME'));
          });
        }
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => AppRoutes.goHome(context),
              child: const Text('Back to Schedule'),
            ),
          ),
        );
      },
    ));

    // Home -> search -> "it's a match" screen
    navigatorKey.currentState!.pushNamed('/searching');
    await tester.pumpAndSettle();
    navigatorKey.currentState!.pushNamed('/its-a-match');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Back to Schedule'));
    await tester.pumpAndSettle();

    expect(find.text('HOME'), findsOneWidget);
    // The old home was removed, so Android back does not go to another home
    expect(navigatorKey.currentState!.canPop(), isFalse);
    expect(homesBuilt, 2); // the first one and the new one, never two alive at the same time
  });
}
