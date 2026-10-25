import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:gapfinderfrontend_dart/core/network/api_config.dart';

// Tells the rest of the app if there is internet. It is a singleton because there is one network:
// every ViewModel must see the same state and the platform is listened to only once.
class ConnectivityService {
  static final ConnectivityService instance = ConnectivityService._();
  ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  final _controller = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  Future<bool>? _checking;
  Timer? _retryTimer;
  static const retryEvery = Duration(seconds: 15);
  bool _isOnline = true;
  bool _initialized = false;

  // Last known state (assumes online until the first check says otherwise)
  bool get isOnline => _isOnline;

  // Emits only when the state really changes
  Stream<bool> get onStatusChange => _controller.stream;

  // Starts listening to the network; the first check runs in the background
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _subscription = _connectivity.onConnectivityChanged.listen((_) => checkNow());
    checkNow();
  }

  // Checks the connection for real.
  // Being connected to wifi (or mobile data) does not mean having internet: the router can be
  // without service or the network can be a captive portal. So when the platform says there is a
  // network, a light request to the API must also answer before saying true.
  Future<bool> checkNow() {
    return _checking ??= _check().whenComplete(() => _checking = null);
  }

  Future<bool> _check() async {
    var online = false;
    try {
      final results = await _connectivity.checkConnectivity();
      final hasNetwork = results.any((r) => r != ConnectivityResult.none);

      if (hasNetwork) {
        // Any answer from the server means it is reachable (even 401 or 404)
        await http.head(Uri.parse(ApiConfig.baseUrl)).timeout(const Duration(seconds: 4));
        online = true;
      }
    } catch (e) {
      debugPrint('Sin conexión con la API: $e');
    }

    _setOnline(online);
    return online;
  }

  void _setOnline(bool online) {
    if (online == _isOnline) return;
    _isOnline = online;
    _controller.add(online);

    // The platform only warns when the network type changes. If the wifi stays connected and the
    // internet comes back later, nobody would notice, so while offline we ask again every 15 seconds.
    _retryTimer?.cancel();
    _retryTimer = online ? null : Timer.periodic(retryEvery, (_) => checkNow());
  }

  // Only for the app shutdown or tests
  Future<void> dispose() async {
    _retryTimer?.cancel();
    _retryTimer = null;
    await _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
}
