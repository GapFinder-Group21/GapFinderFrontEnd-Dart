import 'package:flutter/foundation.dart';
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

// Best candidate found: open the "match found" screen
class CandidateFound extends SearchOutcome {
  final int currentGapId;
  final MatchCandidate candidate;
  CandidateFound(this.currentGapId, this.candidate);
}

// Looks for match candidates for the current gap
class SearchingMatchViewModel extends ChangeNotifier {
  final int userId;
  final MatchModeEnum mode;
  final GapService _gapService;
  final MatchService _matchService;

  SearchingMatchViewModel(
    this.userId,
    this.mode, {
    GapService? gapService,
    MatchService? matchService,
  })  : _gapService = gapService ?? GapService(),
        _matchService = matchService ?? MatchService();

  bool _cancelled = false;

  // Finds the current gap, asks for candidates and picks the best one - GET /matches/gap/{gapId}/candidates.
  // The back returns no candidates when the current gap already has an accepted or completed match,
  // so in that case it returns the accepted match of that gap (a completed one just gives NoMatches).
  // Returns null when the search was cancelled.
  Future<SearchOutcome?> search() async {
    try {
      final gaps = await _gapService.getUserGaps(userId);
      final now = DateTime.now();
      final currentGap = gaps.where((g) => !now.isBefore(g.startTime) && now.isBefore(g.endTime)).firstOrNull;

      if (_cancelled) return null;

      if (currentGap == null) {
        return NoMatches();
      }

      final results = await _matchService.getCandidates(
        currentGap.id,
        useSameCareer: mode == MatchModeEnum.career,
        useSharedInterests: mode == MatchModeEnum.interests,
        useEffort: mode == MatchModeEnum.effort,
      );

      if (_cancelled) return null;

      if (results.isEmpty) {
        final allMatches = await _matchService.getAll();
        final activeMatch = allMatches.where((m) =>
          (m.proposerGapId == currentGap.id || m.acceptorGapId == currentGap.id) &&
          m.status == MatchStatusEnum.ACCEPTED
        ).firstOrNull;
        if (activeMatch != null) {
          if (_cancelled) return null;
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

      if (_cancelled) return null;

      return CandidateFound(currentGap.id, bestCandidate);
    } catch (e) {
      debugPrint('Error searching match: $e');
      if (!_cancelled) {
        return NoMatches();
      }
      return null;
    }
  }

  // Stops the search (its result is ignored)
  void cancel() {
    _cancelled = true;
  }
}
