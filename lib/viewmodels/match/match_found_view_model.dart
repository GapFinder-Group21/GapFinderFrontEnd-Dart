import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';

// Best candidate found and the action to send the match request
class MatchFoundViewModel extends ChangeNotifier {
  final int userId;
  final int currentGapId;
  final MatchCandidate candidate;
  final MatchModeEnum selectedMode;
  final MatchService _matchService;
  final MiguelLocalCache _localCache;

  MatchFoundViewModel({
    required this.userId,
    required this.currentGapId,
    required this.candidate,
    required this.selectedMode,
    MatchService? matchService,
    MiguelLocalCache? localCache,
  })  : _matchService = matchService ?? MatchService(),
        _localCache = localCache ?? MiguelLocalCache.instance;

  bool _isLoading = false;
  String? _errorMessage;
  bool _disposed = false;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // Sends the match request - POST /matches/request
  // Returns the created match, or null on error (see errorMessage)
  Future<Match?> connect() async {
    _isLoading = true;
    _notify();
    try {
      final match = await _matchService.sendRequest(
        currentGapId,
        candidate.acceptorGap.id,
        candidate.score,
      );
      // Cached on network response: the candidate that was shown, with the id of its match
      _localCache.saveSeenCandidate(match.id, candidate);
      return match;
    } catch (e) {
      // The spinner only stops on error; on success the screen is replaced
      _isLoading = false;
      _errorMessage = 'Error: ${e.toString().replaceAll('Exception: ', '')}';
      _notify();
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
