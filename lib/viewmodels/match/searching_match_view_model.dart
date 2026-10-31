import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';

// Result of a match search
sealed class SearchOutcome {}

// No gap now or no candidates: show the "no matches" dialog
class NoMatches extends SearchOutcome {}

// The current gap already has an accepted match: open it
class ExistingMatch extends SearchOutcome {
  final int matchId;
  final User? candidateUser;
  ExistingMatch(this.matchId, this.candidateUser);
}

// The search failed for another reason (not the connection): show the message and offer to retry
class SearchError extends SearchOutcome {
  final String message;
  SearchError(this.message);
}

// Best candidate found: open the "match found" screen
class CandidateFound extends SearchOutcome {
  final int currentGapId;
  final MatchCandidate candidate;
  CandidateFound(this.currentGapId, this.candidate);
}

// Looks for match candidates for the current gap.
// The search needs the back: if the connection is lost while it runs, it is cancelled and the
// screen offers "Reintentar" instead of waiting forever.
class SearchingMatchViewModel extends ChangeNotifier {
  // Each request of the search waits at most this long
  static const requestTimeout = Duration(seconds: 20);

  final int userId;
  final MatchModeEnum mode;
  final GapService _gapService;
  final MatchService _matchService;
  final ConnectivityService _connectivity;

  SearchingMatchViewModel(
    this.userId,
    this.mode, {
    GapService? gapService,
    MatchService? matchService,
    ConnectivityService? connectivity,
  })  : _gapService = gapService ?? GapService(),
        _matchService = matchService ?? MatchService(),
        _connectivity = connectivity ?? ConnectivityService.instance {
    _connectivitySub = _connectivity.onStatusChange.listen((online) {
      if (!online) _markConnectionLost();
    });
  }

  StreamSubscription<bool>? _connectivitySub;
  bool _cancelled = false;
  // Id of the newest search: results and errors of older searches are ignored
  int _searchId = 0;
  bool _connectionLost = false;
  bool _isCheckingConnection = false;
  bool _disposed = false;

  // True when the connection was lost during the search (the screen shows "Reintentar")
  bool get connectionLost => _connectionLost;
  bool get isCheckingConnection => _isCheckingConnection;

  // Cancels the search because there is no connection
  void _markConnectionLost() {
    if (_cancelled) return;
    _cancelled = true;
    _connectionLost = true;
    _notify();
  }

  // "Reintentar": checks the connection and, if it is back, lets the View search again.
  // Returns true when the search can start again.
  Future<bool> retry() async {
    _isCheckingConnection = true;
    _notify();

    final online = await _connectivity.checkNow();
    _isCheckingConnection = false;
    if (online) {
      _cancelled = false;
      _connectionLost = false;
    }
    _notify();
    return online;
  }

  // Finds the current gap, asks for candidates and picks the best one - GET /matches/gap/{gapId}/candidates.
  // The back returns no candidates when the current gap already has an accepted or completed match,
  // so in that case it returns the accepted match of that gap (a completed one just gives NoMatches).
  // Returns null when the search was cancelled.
  Future<SearchOutcome?> search() async {
    final id = ++_searchId;
    // True when this search was cancelled or a newer one started
    bool stale() => _cancelled || id != _searchId;

    // Without connection there is nothing to search: go straight to the "lost connection" state
    if (!_connectivity.isOnline) {
      _markConnectionLost();
      return null;
    }

    try {
      final gaps = await _gapService.getUserGaps(userId).timeout(requestTimeout);
      final now = DateTime.now();
      final currentGap = gaps.where((g) => !now.isBefore(g.startTime) && now.isBefore(g.endTime)).firstOrNull;

      if (stale()) return null;

      if (currentGap == null) {
        return NoMatches();
      }

      final results = await _matchService.getCandidates(
        currentGap.id,
        useSameCareer: mode == MatchModeEnum.career,
        useSharedInterests: mode == MatchModeEnum.interests,
        useEffort: mode == MatchModeEnum.effort,
      ).timeout(requestTimeout);

      if (stale()) return null;

      if (results.isEmpty) {
        final allMatches = await _matchService.getByUser(userId).timeout(requestTimeout);
        if (stale()) return null;
        final activeMatch = allMatches.where((m) =>
          (m.proposerGapId == currentGap.id || m.acceptorGapId == currentGap.id) &&
          m.status == MatchStatusEnum.ACCEPTED
        ).firstOrNull;
        if (activeMatch != null) {
          if (stale()) return null;
          // The other person is the owner of the gap that is not yours
          final isProposer = activeMatch.proposerGap?.user?.id == userId;
          final candidateUser = isProposer
              ? activeMatch.acceptorGap?.user
              : activeMatch.proposerGap?.user;
          return ExistingMatch(activeMatch.id, candidateUser);
        }

        return NoMatches();
      }

      final bestCandidate = results.first;

      if (stale()) return null;

      return CandidateFound(currentGap.id, bestCandidate);
    } catch (e) {
      debugPrint('Error searching match: $e');
      // An older search that fails must not change the state of the newer one
      if (id != _searchId) return null;
      // A network failure is not "no matches": it is a lost connection
      if (isNetworkError(e)) {
        _markConnectionLost();
        return null;
      }
      // Any other error is not "no matches" either: the screen says it failed and offers to retry
      if (!_cancelled) {
        return SearchError(userMessage(e, network: 'No pudimos buscar un match. Intenta de nuevo'));
      }
      return null;
    }
  }

  // Stops the search (its result is ignored)
  void cancel() {
    _cancelled = true;
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
