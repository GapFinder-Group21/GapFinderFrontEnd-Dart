import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../models/match.dart';
import '../../models/match_status_enum.dart';
import '../../models/user.dart';
import '../../services/match_service.dart';

/// Waits for the other person to accept or decline the match request you sent.
class WaitingScreen extends StatefulWidget {
  final int matchId;
  final int requesterId;
  final User? candidateUser;

  const WaitingScreen({
    super.key,
    required this.matchId,
    required this.requesterId,
    this.candidateUser,
  });

  @override
  State<WaitingScreen> createState() => _WaitingScreenState();
}

class _WaitingScreenState extends State<WaitingScreen> {
  final _matchService = MatchService();
  Timer? _pollTimer;
  bool _cancelled = false;

  @override
  // Start checking the match status
  void initState() {
    super.initState();
    _startPolling();
  }

  // Checks the match every 3 seconds - GET /matches/{id}.
  // Accepted -> "It's a match" screen. Rejected -> show a dialog.
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_cancelled || !mounted) return;
      try {
        final Match match = await _matchService.getById(widget.matchId);
        if (_cancelled || !mounted) return;

        if (match.status == MatchStatusEnum.ACCEPTED) {
          _pollTimer?.cancel();
          Navigator.pushReplacementNamed(
            context,
            '/its-a-match',
            arguments: {
              'matchId': match.id,
              'candidateUser': widget.candidateUser,
            },
          );
        } else if (match.status == MatchStatusEnum.REJECTED) {
          _pollTimer?.cancel();
          _showRejectedDialog();
        }
      } catch (e) {
        debugPrint('Error polling match status: $e');
      }
    });
  }

  // Dialog shown when the other person declines
  void _showRejectedDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Request Declined', style: AppFonts.display(weight: FontWeight.w800)),
        content: Text('The other user declined your match request.', style: AppFonts.body()),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context); // Pop dialog
              Navigator.pop(context); // Pop screen
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  // Stop the timer when leaving the screen
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  // Stops waiting and goes back
  void _cancel() {
    _cancelled = true;
    _pollTimer?.cancel();
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
                'WAITING FOR RESPONSE...',
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 22,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'We sent your connection request. Waiting for them to accept.',
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
                    'Cancel Request',
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
