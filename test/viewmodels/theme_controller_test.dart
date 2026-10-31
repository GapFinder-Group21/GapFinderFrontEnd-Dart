import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:gapfinderfrontend_dart/viewmodels/theme/theme_controller.dart';

void main() {
  const settle = Duration(milliseconds: 300);
  const half = Duration(milliseconds: 150);
  const more = Duration(milliseconds: 200);

  late ThemeController controller;

  setUp(() => controller = ThemeController(settle: settle));
  tearDown(() => controller.dispose());

  test('S-20: covering the sensor for a moment does not turn the app dark', () async {
    controller.onLux(2);
    await Future<void>.delayed(half);
    controller.onLux(20); // the hand moved away before the settle time

    await Future<void>.delayed(settle + more);

    expect(controller.themeMode, ThemeMode.system);
  });

  test('S-20: the dark reading is dropped when the light comes back before the settle time', () async {
    controller.onLux(2);
    await Future<void>.delayed(half);
    controller.onLux(500); // now the light asks for "light": the dark change is cancelled

    await Future<void>.delayed(half);

    expect(controller.themeMode, ThemeMode.system); // neither has settled yet
  });

  test('S-20: dark only after the light stays low for the settle time', () async {
    controller.onLux(2);
    controller.onLux(3);
    expect(controller.themeMode, ThemeMode.system);

    await Future<void>.delayed(settle + more);

    expect(controller.themeMode, ThemeMode.dark);
  });

  test('S-20: back to light only after the light stays high for the settle time', () async {
    controller.onLux(2);
    await Future<void>.delayed(settle + more);
    expect(controller.themeMode, ThemeMode.dark);

    controller.onLux(100);
    expect(controller.themeMode, ThemeMode.dark);
    await Future<void>.delayed(settle + more);

    expect(controller.themeMode, ThemeMode.light);
  });

  test('a reading between 10 and 30 lux cancels the change and keeps the mode', () async {
    controller.onLux(2);
    await Future<void>.delayed(half);
    controller.onLux(20);

    await Future<void>.delayed(settle + more);

    expect(controller.themeMode, ThemeMode.system);
  });

  test('a -1 reading of the plugin is ignored', () async {
    controller.onLux(2);
    controller.onLux(-1);

    await Future<void>.delayed(settle + more);

    expect(controller.themeMode, ThemeMode.dark);
  });
}
