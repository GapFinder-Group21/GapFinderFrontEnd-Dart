import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener, AppLifecycleState;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:light/light.dart';
import 'package:gapfinderfrontend_dart/core/perf/perf_log.dart';

// Switches the app to dark mode when the ambient light is low and back to light mode when it is bright
class ThemeController extends ChangeNotifier {
  // Hysteresis: dark below 10 lux, light above 30 lux, in between keeps the current mode
  static const double darkBelowLux = 10;
  static const double lightAboveLux = 30;

  // Smoothing: the reading must stay on the same side for this long before the mode changes, so covering
  // the sensor with a hand or a shadow for a moment does not flip the whole app
  static const Duration settleTime = Duration(seconds: 3);

  final Duration _settle;
  // Kept to listen again when the app comes back (null = the real sensor)
  final Stream<int>? _lightStream;
  AppLifecycleListener? _lifecycle;
  bool _inBackground = false;
  Timer? _pendingTimer;
  ThemeMode? _pendingMode;
  StreamSubscription<int>? _subscription;
  ThemeMode _themeMode = ThemeMode.system;
  bool _disposed = false;

  // lightStream is only for tests; the real one reads the sensor (Android only)
  ThemeController({Stream<int>? lightStream, Duration settle = settleTime})
      : _settle = settle,
        _lightStream = lightStream {
    _listen(lightStream);
    _watchAppLifecycle();
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
    PerfStats.luxEvent();
    if (lux < 0) return; // the plugin sends -1 when it cannot read the value

    if (lux < darkBelowLux) {
      _settleOn(ThemeMode.dark);
    } else if (lux > lightAboveLux) {
      _settleOn(ThemeMode.light);
    } else {
      _cancelPending(); // in between: the reading is not clear, keep the current mode
    }
  }

  // The mode changes only if the readings keep asking for it during settleTime
  void _settleOn(ThemeMode mode) {
    if (mode == _themeMode) {
      _cancelPending();
      return;
    }
    if (_pendingMode == mode) return; // already waiting for this one

    _cancelPending();
    _pendingMode = mode;
    _pendingTimer = Timer(_settle, () {
      _pendingMode = null;
      _pendingTimer = null;
      _setMode(mode);
    });
  }

  void _cancelPending() {
    _pendingTimer?.cancel();
    _pendingTimer = null;
    _pendingMode = null;
  }

  // Without a Flutter binding (plain unit tests) there is no listener: tests call handleAppLifecycle
  void _watchAppLifecycle() {
    try {
      _lifecycle = AppLifecycleListener(onStateChange: handleAppLifecycle);
    } catch (_) {}
  }

  // Micro-optimización (lifecycle): the light sensor is off while the app is in the background
  // (the current mode stays; readings start again when the app comes back)
  @visibleForTesting
  void handleAppLifecycle(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      if (_inBackground) return;
      _inBackground = true;
      _cancelPending();
      _subscription?.cancel();
      _subscription = null;
    } else if (state == AppLifecycleState.resumed && _inBackground) {
      _inBackground = false;
      _listen(_lightStream);
    }
  }

  // If the sensor fails, go back to the system theme and keep the app working
  void _onSensorError(Object error) {
    debugPrint('Light sensor error: $error');
    _cancelPending();
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
    _lifecycle?.dispose();
    _cancelPending();
    _subscription?.cancel();
    super.dispose();
  }
}
