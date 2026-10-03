import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../models/match_candidate.dart';
import '../../models/match_mode_enum.dart';
import '../../services/match_service.dart';
import '../../widgets/common/avatar_widget.dart';
import '../../core/widgets/custom_button.dart';

/// Shows the best candidate found for the current gap and lets the user send the match request.
class MatchFoundScreen extends StatefulWidget {
  final int userId;
  final int currentGapId;
  final MatchCandidate candidate;
  final MatchModeEnum selectedMode;

  const MatchFoundScreen({
    super.key,
    required this.userId,
    required this.currentGapId,
    required this.candidate,
    required this.selectedMode,
  });

  @override
  State<MatchFoundScreen> createState() => _MatchFoundScreenState();
}

class _MatchFoundScreenState extends State<MatchFoundScreen> {
  final _matchService = MatchService();
  bool _isLoading = false;

  // Sends the match request and goes to the waiting screen - POST /matches/request
  Future<void> _connectNow() async {
    setState(() => _isLoading = true);
    try {
      final match = await _matchService.sendRequest(
        widget.currentGapId,
        widget.candidate.acceptorGap.id,
        widget.candidate.score,
      );

      if (!mounted) return;

      Navigator.pushReplacementNamed(
        context,
        '/waiting-match',
        arguments: {
          'matchId': match.id,
          'requesterId': widget.userId,
          'candidateUser': widget.candidate.acceptorGap.user,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString().replaceAll('Exception: ', '')}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidateUser = widget.candidate.acceptorGap.user;
    final scorePercent = widget.candidate.score;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Text(
                'MATCH FOUND!',
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 24,
                  color: AppColors.contrast,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              AvatarWidget(url: candidateUser?.avatarUrl, name: candidateUser?.name, size: 100),
              const SizedBox(height: 20),
              Text(
                candidateUser?.name ?? 'User',
                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                  fontSize: 22,
                  color: AppColors.contrast,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${candidateUser?.career ?? ''} · Sem ${candidateUser?.semester ?? 1}',
                style: AppFonts.body().copyWith(
                  fontSize: 14,
                  color: AppColors.contrast.withValues(alpha: 0.5),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accent2.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Compatibility: ${scorePercent.toStringAsFixed(1)}',
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 14,
                    color: AppColors.accent2,
                  ),
                ),
              ),
              const Spacer(),
              _isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        CustomButton(
                          label: 'Connect Now',
                          color: AppColors.accent2,
                          onClick: _connectNow,
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: Text(
                              'Decline',
                              style: AppFonts.body(weight: FontWeight.w700).copyWith(
                                fontSize: 14,
                                color: AppColors.contrast.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }
}
