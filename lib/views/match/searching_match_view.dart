import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/searching_match_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';

/// Loading screen that looks for match candidates for the current gap.
class SearchingMatchView extends StatefulWidget {
  const SearchingMatchView({super.key});

  @override
  State<SearchingMatchView> createState() => _SearchingMatchViewState();
}

class _SearchingMatchViewState extends State<SearchingMatchView> {
  @override
  // Start searching as soon as the screen opens
  void initState() {
    super.initState();
    _searchMatch();
  }

  // Runs the search and opens the screen that fits the result
  Future<void> _searchMatch() async {
    final vm = context.read<SearchingMatchViewModel>();
    final outcome = await vm.search();
    if (outcome == null || !mounted) return;

    switch (outcome) {
      case NoMatches():
        _showNoMatchesDialog();
      case SearchError(:final message):
        _showSearchErrorDialog(message);
      case ExistingMatch(:final matchId, :final candidateUser):
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.itsAMatch,
          arguments: {
            'matchId': matchId,
            'candidateUser': candidateUser,
          },
        );
      case CandidateFound(:final currentGapId, :final candidate):
        Navigator.pushReplacementNamed(
          context,
          AppRoutes.matchFound,
          arguments: {
            'userId': vm.userId,
            'currentGapId': currentGapId,
            'candidate': candidate,
            'selectedMode': vm.mode,
          },
        );
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

  // Dialog shown when the search failed (not "no matches"): retry or go back
  void _showSearchErrorDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text('No pudimos buscar', style: AppFonts.display(weight: FontWeight.w800)),
        content: Text(message, style: AppFonts.body()),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext); // Pop dialog
              Navigator.pop(context); // Pop screen
            },
            child: const Text('Volver'),
          ),
          CustomButton(
            label: 'Reintentar',
            onClick: () {
              Navigator.pop(dialogContext);
              _searchMatch();
            },
          ),
        ],
      ),
    );
  }

  // Stops the search and goes back
  void _cancel() {
    context.read<SearchingMatchViewModel>().cancel();
    Navigator.pop(context);
  }

  // "Reintentar": searches again only if the connection is back
  Future<void> _retry() async {
    final vm = context.read<SearchingMatchViewModel>();
    final online = await vm.retry();
    if (!mounted) return;
    if (online) {
      _searchMatch();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sigues sin conexión')),
      );
    }
  }

  // Shown when the connection was lost during the search
  Widget _buildConnectionLost(SearchingMatchViewModel vm) {
    return Scaffold(
      backgroundColor: AppColors.contrast,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              const Icon(Icons.wifi_off_rounded, size: 72, color: AppColors.accent1),
              const SizedBox(height: 28),
              Text(
                'Se perdió la conexión durante la búsqueda',
                textAlign: TextAlign.center,
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 20,
                  color: Colors.white,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Buscar un match necesita conexión. Cuando vuelva, toca Reintentar.',
                textAlign: TextAlign.center,
                style: AppFonts.body().copyWith(
                  fontSize: 14,
                  color: Colors.white.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 32),
              CustomButton(
                label: vm.isCheckingConnection ? 'Comprobando...' : 'Reintentar',
                onClick: vm.isCheckingConnection ? null : _retry,
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

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<SearchingMatchViewModel>();
    if (vm.connectionLost) return _buildConnectionLost(vm);

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
