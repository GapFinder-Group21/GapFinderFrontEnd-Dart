import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';

// Shared by the ViewModels that must work without internet.
// It listens to ConnectivityService, exposes isOffline and lastUpdated, and calls onRestored
// when the connection comes back so the screen reloads by itself.
mixin OfflineAwareMixin on ChangeNotifier {
  // A network call that takes longer than this falls back to what is saved
  static const loadTimeout = Duration(seconds: 8);

  StreamSubscription<bool>? _connectivitySub;
  bool _isOffline = !ConnectivityService.instance.isOnline;
  DateTime? _lastUpdated;

  // True when there is no connection, or when the network failed and saved data is on screen
  bool get isOffline => _isOffline;

  // When the data on screen was last saved or loaded from the network
  DateTime? get lastUpdated => _lastUpdated;

  // What the connectivity service knows right now
  bool get hasConnection => ConnectivityService.instance.isOnline;

  // Starts listening; the subscription is cancelled in dispose
  void listenToConnectivity({required Future<void> Function() onRestored}) {
    _connectivitySub?.cancel();
    _isOffline = !hasConnection;
    // Estrategia: Stream. The service emits true or false only when the connection changes, so the
    // screen reacts when it happens instead of asking all the time.
    _connectivitySub = ConnectivityService.instance.onStatusChange.listen((online) {
      _isOffline = !online;
      notifyListeners();
      if (online) onRestored();
    });
  }

  // The network answered: the screen shows fresh data
  void markFresh() {
    _isOffline = false;
    _lastUpdated = DateTime.now();
  }

  // Saved data is on screen (no connection, or the network failed)
  void markFromCache(DateTime? savedAt) {
    _isOffline = true;
    _lastUpdated = savedAt;
  }

  // Only the time changes (for example a saved file that is still fresh)
  void markUpdatedAt(DateTime? at) {
    _lastUpdated = at;
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    super.dispose();
  }
}
