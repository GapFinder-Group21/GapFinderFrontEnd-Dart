import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/waiting_view_model.dart';

/// Waits for the other person to accept or decline the match request you sent.
class WaitingView extends StatefulWidget {
  const WaitingView({super.key});

  @override
  State<WaitingView> createState() => _WaitingViewState();
}

class _WaitingViewState extends State<WaitingView> {
  StreamSubscription<WaitingEvent>? _eventsSub;

  @override
  // Listen to the polling result
  void initState() {
    super.initState();
    final vm = context.read<WaitingViewModel>();
    _eventsSub = vm.events.listen((event) {
      if (!mounted) return;
      switch (event) {
        case MatchAccepted(:final match):
          Navigator.pushReplacementNamed(
            context,
            AppRoutes.itsAMatch,
            arguments: {
              'matchId': match.id,
              'candidateUser': vm.candidateUser,
            },
          );
        case MatchRejected():
          _showRejectedDialog();
      }
    });
  }

  @override
  void dispose() {
    _eventsSub?.cancel();
    super.dispose();
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

  // Stops waiting and goes back
  void _cancel() {
    context.read<WaitingViewModel>().cancel();
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
