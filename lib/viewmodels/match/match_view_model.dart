import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';

// State and logic of the match tab.
// Network falling back to cache: the gap and the match come from the back and, without connection
// (or if it fails), from what was saved. Looking for a match always needs the back.
class MatchViewModel extends ChangeNotifier {
  // The tab never waits longer than this for the back
  static const loadTimeout = Duration(seconds: 20);

  final GapService _gapService;
  final MatchService _matchService;
  final JoelLocalCache _localCache;
  final ConnectivityService _connectivity;

  MatchViewModel({
    GapService? gapService,
    MatchService? matchService,
    JoelLocalCache? localCache,
    ConnectivityService? connectivity,
  })  : _gapService = gapService ?? GapService(),
        _matchService = matchService ?? MatchService(),
        _localCache = localCache ?? JoelLocalCache.instance,
        _connectivity = connectivity ?? ConnectivityService.instance;

  StreamSubscription<bool>? _connectivitySub;
  bool _isOffline = false;
  DateTime? _lastUpdated;

  MatchModeEnum _selectedMode = MatchModeEnum.career;
  Gap? _currentGap;
  Match? _gapMatch;
  int? _userId;
  // Ids of the user's gaps, to know which matches are theirs when caching
  Set<int> _userGapIds = {};
  DateTime? _lastCheckTime;
  bool _isLoading = true;
  int _loadId = 0;
  bool _disposed = false;

  MatchModeEnum get selectedMode => _selectedMode;
  // Gap the user is in right now (null while loading)
  Gap? get currentGap => _isLoading ? null : _currentGap;
  // Accepted or completed match of the current gap (null while loading)
  Match? get gapMatch => _isLoading ? null : _gapMatch;
  int? get userId => _userId;
  DateTime? get lastCheckTime => _lastCheckTime;
  bool get isLoading => _isLoading;

  bool get isOffline => _isOffline;
  // When the gap and the match on screen were last updated (the network answer or the saved copy)
  DateTime? get lastUpdated => _lastUpdated;

  // The user can look for a match only in a gap that has no booked match, and with connection
  // (the search asks the back for candidates)
  bool get canMatch => currentGap != null && gapMatch == null && !_isOffline;

  // An accepted match whose meeting has not ended yet (the back moves it to COMPLETED every 5 minutes)
  bool get isOngoing =>
      gapMatch != null &&
      gapMatch!.status == MatchStatusEnum.ACCEPTED &&
      gapMatch!.endTime.isAfter(DateTime.now());

  void selectMode(MatchModeEnum mode) {
    _selectedMode = mode;
    _notify();
  }

  // Load the current gap and its match, and listen to the connection
  Future<void> init() {
    _isOffline = !_connectivity.isOnline;
    _connectivitySub ??= _connectivity.onStatusChange.listen(_onConnectivityChanged);
    return refresh();
  }

  // Back online: reload by itself. Offline: keep what is on screen and block the search
  void _onConnectivityChanged(bool online) {
    _isOffline = !online;
    _notify();
    if (online) refresh();
  }

  // Pull to refresh: checks the connection for real first, so it can notice it is back
  Future<void> pullToRefresh() async {
    await _connectivity.checkNow();
    _isOffline = !_connectivity.isOnline;
    await refresh();
  }

  // Loads the current gap and then the match of that gap
  Future<void> refresh() async {
    final loadId = ++_loadId;
    _isLoading = true;
    _notify();

    final gap = await _loadActiveGap();
    final match = await _loadGapMatch(gap);

    // A newer reload already started, so this result is old
    if (loadId != _loadId) return;
    _currentGap = gap;
    _gapMatch = match;
    _isLoading = false;
    _notify();
  }

  // Finds the gap the user is in right now - GET /gaps/user/{userId}
  Future<Gap?> _loadActiveGap() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) return null;
    _userId = userId;

    final now = DateTime.now();
    _lastCheckTime = now;
    _notify();

    List<Gap>? gaps;
    if (!_isOffline) {
      try {
        gaps = await _gapService.getUserGaps(userId).timeout(loadTimeout);
        _localCache.saveGaps(userId, gaps);
        _lastUpdated = now;
      } catch (e) {
        debugPrint("Advertencia: No se pudieron cargar los GAPs en Match: $e");
      }
    }

    // No connection (or the back failed): the gaps saved the last time
    if (gaps == null) {
      gaps = await _localCache.safeRead('gaps', () => _localCache.gaps.get(userId));
      _lastUpdated = await _localCache.safeRead('gaps date', () => _localCache.gaps.savedAt(userId));
    }
    if (gaps == null) return null;

    _userGapIds = gaps.map((g) => g.id).toSet();
    return gaps.where((g) => !now.isBefore(g.startTime) && now.isBefore(g.endTime)).firstOrNull;
  }

  // Finds the accepted or completed match of the current gap - GET /matches
  // Same rule as the back: only the current gap counts, matches of other gaps do not block.
  // Without connection (or if the back fails) it looks in the matches saved in SQLite.
  Future<Match?> _loadGapMatch(Gap? gap) async {
    if (gap == null) return null;

    List<Match>? all;
    if (!_isOffline) {
      try {
        all = await _matchService.getAll().timeout(loadTimeout);
        _cacheUserMatches(all);
      } catch (e) {
        debugPrint('❌ [MatchMainScreen] Error loading the match of the gap: $e');
      }
    }

    if (all == null) {
      final userId = _userId;
      if (userId == null) return null;
      all = await _localCache.safeRead('matches', () => _localCache.matches.getAllForUser(userId));
      if (all == null) return null;
    }

    final booked = all.where((m) =>
      (m.proposerGapId == gap.id || m.acceptorGapId == gap.id) &&
      (m.status == MatchStatusEnum.ACCEPTED || m.status == MatchStatusEnum.COMPLETED)
    ).firstOrNull;

    if (booked != null) {
      debugPrint('🔒 [MatchMainScreen] Gap ${gap.id} already has match ID=${booked.id} (${booked.status.name}), blocking match button.');
    } else {
      debugPrint('🔓 [MatchMainScreen] Gap ${gap.id} has no accepted or completed match.');
    }
    return booked;
  }

  // Cached on network response: only the matches of the user's gaps (never blocks the screen)
  void _cacheUserMatches(List<Match> all) {
    final userId = _userId;
    if (userId == null) return;
    final gapIds = _userGapIds;
    final mine = all
        .where((m) => gapIds.contains(m.proposerGapId) || gapIds.contains(m.acceptorGapId))
        .toList();
    _localCache.saveMatches(userId, mine, gapIds);
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
