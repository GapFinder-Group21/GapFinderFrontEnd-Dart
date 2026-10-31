import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_found_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/open_tables/cached_avatar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';

/// Shows the best candidate found for the current gap and lets the user send the match request.
class MatchFoundView extends StatelessWidget {
  const MatchFoundView({super.key});

  // Sends the match request and goes to the waiting screen
  Future<void> _connectNow(BuildContext context) async {
    final vm = context.read<MatchFoundViewModel>();
    final match = await vm.connect();
    if (!context.mounted) return;

    if (match != null) {
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.waitingMatch,
        arguments: {
          'matchId': match.id,
          'requesterId': vm.userId,
          'candidateUser': vm.candidate.acceptorGap.user,
        },
      );
    } else {
      // Queued (no internet) or failed
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vm.takeNotice() ?? vm.errorMessage ?? '')),
      );
    }
  }

  // With a request waiting in the outbox it is cancelled first, so it is not sent later
  Future<void> _decline(BuildContext context) async {
    await context.read<MatchFoundViewModel>().cancelRequest();
    if (!context.mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MatchFoundViewModel>();
    final candidateUser = vm.candidate.acceptorGap.user;
    final scorePercent = vm.candidate.score;

    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          children: [
            if (vm.isOffline) const OfflineBanner(message: MatchFoundViewModel.offlineBanner),
            Expanded(child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              Text(
                'MATCH FOUND!',
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 24,
                  color: context.palette.contrast,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 32),
              // Kept on disk by cached_network_image: it still shows without internet after it loaded once
              CachedAvatar(url: candidateUser?.avatarUrl, name: candidateUser?.name, size: 100),
              const SizedBox(height: 20),
              Text(
                candidateUser?.name ?? 'User',
                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                  fontSize: 22,
                  color: context.palette.contrast,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${candidateUser?.career ?? ''} · Sem ${candidateUser?.semester ?? 1}',
                style: AppFonts.body().copyWith(
                  fontSize: 14,
                  color: context.palette.contrast.withValues(alpha: 0.5),
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
              vm.isLoading
                  ? const CircularProgressIndicator()
                  : Column(
                      children: [
                        // Pending: the request is queued, so the button is off
                        CustomButton(
                          label: vm.wasSent
                              ? 'Solicitud enviada'
                              : vm.isConnectPending
                                  ? 'Pendiente de enviar'
                                  : 'Connect Now',
                          color: AppColors.accent2,
                          onClick: vm.isConnectPending || vm.wasSent ? null : () => _connectNow(context),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: TextButton(
                            onPressed: () => _decline(context),
                            child: Text(
                              vm.isConnectPending ? 'Cancelar solicitud' : 'Decline',
                              style: AppFonts.body(weight: FontWeight.w700).copyWith(
                                fontSize: 14,
                                color: context.palette.contrast.withValues(alpha: 0.4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
              const SizedBox(height: 16),
            ],
          ),
        )),
          ],
        ),
      ),
    );
  }
}
