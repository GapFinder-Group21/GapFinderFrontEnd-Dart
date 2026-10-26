import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:light/light.dart';

// Switches the app to dark mode when the ambient light is low and back to light mode when it is bright
class ThemeController extends ChangeNotifier {
  // Hysteresis: dark below 10 lux, light above 30 lux, in between keeps the current mode
  static const double darkBelowLux = 10;
  static const double lightAboveLux = 30;

  StreamSubscription<int>? _subscription;
  ThemeMode _themeMode = ThemeMode.system;
  bool _disposed = false;

  // lightStream is only for tests; the real one reads the sensor (Android only)
  ThemeController({Stream<int>? lightStream}) {
    _listen(lightStream);
  }

  // system until the sensor gives a clear reading, and always on iOS or when there is no sensor
  ThemeMode get themeMode => _themeMode;

  void _listen(Stream<int>? lightStream) {
    try {
      // iOS has no public light sensor API, there the app follows the system theme
      final stream = lightStream ?? (!kIsWeb && Platform.isAndroid ? Light().lightSensorStream : null);
      if (stream == null) return;
      // Estrategia: Stream. The light sensor sends a lux reading every time the light changes.
      _subscription = stream.listen(onLux, onError: _onSensorError, cancelOnError: false);
    } catch (e) {
      debugPrint('Light sensor not available: $e');
    }
  }

  // Applies one reading; the mode only changes (and notifies) when it really changes
  @visibleForTesting
  void onLux(int lux) {
    if (lux < 0) return; // the plugin sends -1 when it cannot read the value

    if (lux < darkBelowLux) {
      _setMode(ThemeMode.dark);
    } else if (lux > lightAboveLux) {
      _setMode(ThemeMode.light);
    }
  }

  // If the sensor fails, go back to the system theme and keep the app working
  void _onSensorError(Object error) {
    debugPrint('Light sensor error: $error');
    _setMode(ThemeMode.system);
  }

  void _setMode(ThemeMode mode) {
    if (mode == _themeMode || _disposed) return;
    _themeMode = mode;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    super.dispose();
  }
}
