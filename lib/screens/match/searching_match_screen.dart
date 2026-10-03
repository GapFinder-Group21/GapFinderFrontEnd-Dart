import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../models/match_candidate.dart';
import '../../models/match_mode_enum.dart';
import '../../models/match_status_enum.dart';
import '../../services/gap_service.dart';
import '../../services/match_service.dart';
import '../../core/widgets/custom_button.dart';

/// Loading screen that looks for match candidates for the current gap.
class SearchingMatchScreen extends StatefulWidget {
  final int userId;
  final MatchModeEnum mode;

  const SearchingMatchScreen({
    super.key,
    required this.userId,
    required this.mode,
  });

  @override
  State<SearchingMatchScreen> createState() => _SearchingMatchScreenState();
}

class _SearchingMatchScreenState extends State<SearchingMatchScreen> {
  final _gapService = GapService();
  final _matchService = MatchService();
  bool _cancelled = false;

  @override
  // Start searching as soon as the screen opens
  void initState() {
    super.initState();
    _searchMatch();
  }

  // Finds the current gap, asks for candidates and opens the best one - GET /matches/gap/{gapId}/candidates.
  // If there are no candidates but the user already has an accepted match, it opens that match.
  Future<void> _searchMatch() async {
    try {
      final gaps = await _gapService.getUserGaps(widget.userId);
      final now = DateTime.now();
      final currentGap = gaps.where((g) => !now.isBefore(g.startTime) && now.isBefore(g.endTime)).firstOrNull;

      if (_cancelled || !mounted) return;

      if (currentGap == null) {
        _showNoMatchesDialog();
        return;
      }

      final results = await _matchService.getCandidates(
        currentGap.id,
        useSameCareer: widget.mode == MatchModeEnum.career,
        useSharedInterests: widget.mode == MatchModeEnum.interests,
        useEffort: widget.mode == MatchModeEnum.effort,
      );

      if (_cancelled || !mounted) return;

      if (results.isEmpty) {
        final allMatches = await _matchService.getAll();
        final activeMatch = allMatches.where((m) => 
          (m.proposerGap?.user?.id == widget.userId || m.acceptorGap?.user?.id == widget.userId) &&
          m.status == MatchStatusEnum.ACCEPTED
        ).firstOrNull;
        if (activeMatch != null) {
          if (_cancelled || !mounted) return;
          // The other person is the owner of the gap that is not yours
          final isProposer = activeMatch.proposerGap?.user?.id == widget.userId;
          final candidateUser = isProposer
              ? activeMatch.acceptorGap?.user
              : activeMatch.proposerGap?.user;
          Navigator.pushReplacementNamed(
            context,
            '/its-a-match',
            arguments: {
              'matchId': activeMatch.id,
              'candidateUser': candidateUser,
            },
          );
          return;
        }

        _showNoMatchesDialog();
        return;
      }

      final bestCandidate = results.first;

      if (_cancelled || !mounted) return;

      Navigator.pushReplacementNamed(
        context,
        '/match-found',
        arguments: {
          'userId': widget.userId,
          'currentGapId': currentGap.id,
          'candidate': bestCandidate,
          'selectedMode': widget.mode,
        },
      );
    } catch (e) {
      debugPrint('Error searching match: $e');
      if (!_cancelled && mounted) {
        _showNoMatchesDialog();
      }
    }
  }

  // Dialog shown when no candidate was found
  void _showNoMatchesDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('No Matches Found', style: AppFonts.display(weight: FontWeight.w800)),
        content: Text(
          'We could not find any available candidates matching your preferences right now.',
          style: AppFonts.body(),
        ),
        actions: [
          CustomButton(
            label: 'OK',
            onClick: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pop(context); // Pop screen
            },
          ),
        ],
      ),
    );
  }

  // Stops the search and goes back
  void _cancel() {
    _cancelled = true;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.contrast,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const SizedBox(
                width: 80,
                height: 80,
                child: CircularProgressIndicator(
                  strokeWidth: 4,
                  valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent2),
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'FINDING YOUR MATCH...',
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 22,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Searching for people free right now with similar interests and schedule.',
                textAlign: TextAlign.center,
                style: AppFonts.body().copyWith(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: _cancel,
                  child: Text(
                    'Cancel',
                    style: AppFonts.body(weight: FontWeight.w700).copyWith(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
