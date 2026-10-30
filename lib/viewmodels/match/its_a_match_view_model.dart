import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';

// "It's a match" screen: shows the match that was saved on the device (read only).
// With connection it also updates it from the back; without connection the actions that
// need the network are disabled.
class ItsAMatchViewModel extends ChangeNotifier {
  // The refresh never waits longer than this for the back
  static const refreshTimeout = Duration(seconds: 15);

  final int matchId;
  final MatchService _matchService;
  final JoelLocalCache _localCache;
  final ConnectivityService _connectivity;

  ItsAMatchViewModel(
    this.matchId, {
    MatchService? matchService,
    JoelLocalCache? localCache,
    ConnectivityService? connectivity,
  })  : _matchService = matchService ?? MatchService(),
        _localCache = localCache ?? JoelLocalCache.instance,
        _connectivity = connectivity ?? ConnectivityService.instance;

  StreamSubscription<bool>? _connectivitySub;
  Match? _match;
  bool _isOffline = false;
  bool _isRefreshing = false;
  DateTime? _lastUpdated;
  bool _disposed = false;

  // The saved match (null if it was never saved and there is no connection)
  Match? get match => _match;
  bool get isOffline => _isOffline;
  bool get isRefreshing => _isRefreshing;
  // When the match on screen was last updated (the network answer or the saved copy)
  DateTime? get lastUpdated => _lastUpdated;

  // Shows the saved match at once and, with connection, updates it
  Future<void> init() async {
    _isOffline = !_connectivity.isOnline;
    _connectivitySub = _connectivity.onStatusChange.listen(_onConnectivityChanged);
    await _loadSaved();
    if (!_isOffline) await refresh();
  }

  // Back online: update the match by itself
  void _onConnectivityChanged(bool online) {
    _isOffline = !online;
    _notify();
    if (online) refresh();
  }

  Future<void> _loadSaved() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return;

    final saved = await _localCache.safeRead('match', () async {
      final match = await _localCache.matches.getById(matchId);
      if (match == null) return null;
      return (match, await _localCache.matches.savedAtById(matchId));
    });
    // The network already answered while SQLite was read: the saved copy is older, keep the network one
    if (saved == null || _disposed || _lastUpdated != null) return;

    _match = saved.$1;
    _lastUpdated = saved.$2;
    _notify();
  }

  // Updates the match from the back - GET /matches/{id} (needs connection)
  Future<void> refresh() async {
    if (_isOffline || _isRefreshing) return;
    _isRefreshing = true;
    _notify();

    try {
      final match = await _matchService.getById(matchId).timeout(refreshTimeout);
      _match = match;
      _lastUpdated = DateTime.now();

      final userId = await TokenStorage.getUserId();
      if (userId != null) _localCache.saveMatchOfUser(userId, match);
    } catch (e) {
      debugPrint('Error refreshing the match: $e');
    } finally {
      _isRefreshing = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivitySub?.cancel();
    super.dispose();
  }
}
