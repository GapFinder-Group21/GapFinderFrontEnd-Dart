import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/core/utils/display_formatters.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/match_mode_selector.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/animated_match_button.dart';

/// Match tab: shows your current free gap and the button to start looking for a match.
/// The button is disabled if you have no gap now or the current gap already has an
/// accepted or completed match (the back gives no candidates for that gap).
class MatchView extends StatelessWidget {
  const MatchView({super.key});

  // Opens the searching screen with the selected match mode
  Future<void> _startMatch(BuildContext context) async {
    final vm = context.read<MatchViewModel>();
    if (vm.userId == null) return;
    Navigator.pushNamed(
      context,
      AppRoutes.searchingMatch,
      arguments: {'userId': vm.userId, 'mode': vm.selectedMode},
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MatchViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar
            Container(
              width: double.infinity,
              color: AppColors.contrast,
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Text(
                'MATCH',
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 20,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                vm.refresh();
              },
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                  child: Builder(
                    builder: (context) {
                      final isLoading = vm.isLoading;
                      final gap = vm.currentGap;
                      // Accepted or completed match of the current gap
                      final gapMatch = vm.gapMatch;

                      final bool canMatch = vm.canMatch;

                      return Column(
                        children: [
                          // "Current GAP" card
                          if (isLoading)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 20),
                              child: CircularProgressIndicator(),
                            )
                          else if (gap != null)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                              margin: const EdgeInsets.only(bottom: 32),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.accent2.withValues(alpha: 0.3), width: 1.5),
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    top: 0,
                                    bottom: 0,
                                    child: Container(width: 4, color: AppColors.accent2),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'CURRENT GAP',
                                          style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                                            fontSize: 12,
                                            letterSpacing: 1,
                                            color: AppColors.accent2,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          '${DisplayFormatters.time(gap.startTime)} – ${DisplayFormatters.time(gap.endTime)}',
                                          style: AppFonts.display(weight: FontWeight.w800).copyWith(
                                            fontSize: 18,
                                            color: AppColors.contrast,
                                          ),
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Icon(Icons.access_time, size: 13, color: AppColors.accent2),
                                            const SizedBox(width: 4),
                                            Text(
                                              DisplayFormatters.freeDuration(gap.durationMinutes),
                                              style: AppFonts.body().copyWith(
                                                fontSize: 13,
                                                color: AppColors.contrast.withValues(alpha: 0.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                              margin: const EdgeInsets.only(bottom: 32),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: AppColors.contrast.withValues(alpha: 0.1)),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    'You have no active GAP right now.',
                                    textAlign: TextAlign.center,
                                    style: AppFonts.body().copyWith(
                                      fontSize: 14,
                                      color: AppColors.contrast.withValues(alpha: 0.7),
                                    ),
                                  ),
                                  if (vm.lastCheckTime != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'Last check: ${DisplayFormatters.fullDateTime(vm.lastCheckTime!)}',
                                      textAlign: TextAlign.center,
                                      style: AppFonts.body().copyWith(
                                        fontSize: 12,
                                        color: AppColors.contrast.withValues(alpha: 0.4),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),

                          if (gapMatch != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              margin: const EdgeInsets.only(bottom: 24),
                              decoration: BoxDecoration(
                                color: AppColors.accent2.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.accent2.withValues(alpha: 0.2)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.bolt_rounded, color: AppColors.accent2, size: 20),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      vm.isOngoing
                                          ? "YOU HAVE AN ACTIVE MATCH IN THIS GAP!"
                                          : "YOU ALREADY HAD A MATCH IN THIS GAP",
                                      style: AppFonts.body(weight: FontWeight.w800).copyWith(
                                        fontSize: 12,
                                        color: AppColors.accent2,
                                        letterSpacing: 1,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          // Main animated MATCH button
                          AnimatedMatchButton(
                            isEnabled: canMatch,
                            onTap: () => _startMatch(context),
                          ),

                          const SizedBox(height: 28),

                          // Match mode selector (career, interests or effort)
                          MatchModeSelector(
                            selected: vm.selectedMode,
                            onChanged: vm.selectMode,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
