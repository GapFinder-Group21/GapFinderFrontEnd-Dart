import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_invitation_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/avatar_widget.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';

/// Shown when someone sends you a match request: accept or decline it.
class MatchInvitationView extends StatefulWidget {
  const MatchInvitationView({super.key});

  @override
  State<MatchInvitationView> createState() => _MatchInvitationViewState();
}

class _MatchInvitationViewState extends State<MatchInvitationView> {
  @override
  // Load the match details when the screen opens (closes the screen if it fails)
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final ok = await context.read<MatchInvitationViewModel>().init();
    if (!ok && mounted) Navigator.pop(context);
  }

  static const _queuedNotice = 'Tu respuesta a la invitación se enviará cuando vuelva la conexión';

  // Accepts the match and shows the "It's a match" screen
  Future<void> _accept() async {
    final vm = context.read<MatchInvitationViewModel>();
    final answer = await vm.accept();
    if (!mounted) return;

    if (answer == InvitationAnswer.done) {
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.itsAMatch,
        arguments: {
          'matchId': vm.acceptedMatch!.id,
          'candidateUser': vm.acceptedMatch!.proposerGap?.user,
        },
      );
    } else if (answer == InvitationAnswer.queued) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_queuedNotice)),
      );
    } else if (answer == InvitationAnswer.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vm.errorMessage ?? '')),
      );
    }
  }

  // Declines the match and closes the screen
  Future<void> _decline() async {
    final vm = context.read<MatchInvitationViewModel>();
    final answer = await vm.decline();
    if (!mounted) return;

    if (answer == InvitationAnswer.done) {
      Navigator.pop(context);
    } else if (answer == InvitationAnswer.queued) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(_queuedNotice)),
      );
    } else if (answer == InvitationAnswer.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vm.errorMessage ?? '')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MatchInvitationViewModel>();
    if (vm.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // No connection and this invitation was never saved: explain it instead of loading forever
    if (vm.unavailable) return _buildUnavailable(vm);

    final user = vm.match!.proposerGap?.user;
    if (user == null) {
      return const Scaffold(body: Center(child: Text('Match user not found')));
    }

    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          children: [
            // The invitation on screen is the saved one
            if (vm.isOffline)
              OfflineBanner(
                message: 'Sin conexión · mostrando la invitación guardada',
                lastUpdated: vm.lastUpdated,
              ),
            Container(
              width: double.infinity,
              color: AppColors.accent3, // Azul para invitaciones
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              child: Text(
                "Match Invitation!",
                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                  fontSize: 18,
                  color: Colors.white,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SOMEONE WANTS TO CONNECT',
                      style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: context.palette.contrast.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildUserCard(user),
                    const SizedBox(height: 32),
                    
                    Text(
                      'PROPOSAL',
                      style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                        fontSize: 11,
                        letterSpacing: 1.2,
                        color: context.palette.contrast.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: context.palette.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.accent3.withValues(alpha: 0.1)),
                      ),
                      child: Text(
                        "${user.name} found an overlap in your schedules and wants to meet up!",
                        style: AppFonts.body().copyWith(color: context.palette.contrast.withValues(alpha: 0.7)),
                      ),
                    ),

                    const SizedBox(height: 48),
                    
                    vm.isProcessing
                      ? const Center(child: CircularProgressIndicator())
                      : vm.isPending
                      // The answer waits in the outbox: both buttons are replaced by one disabled button
                      ? Column(
                          children: [
                            const CustomButton(
                              label: 'Pendiente de enviar',
                              color: AppColors.accent3,
                              onClick: null,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _queuedNotice,
                              textAlign: TextAlign.center,
                              style: AppFonts.body().copyWith(
                                fontSize: 12,
                                color: context.palette.contrast.withValues(alpha: 0.5),
                              ),
                            ),
                          ],
                        )
                      : vm.isAnswered
                      // The back says it is not pending anymore (answered or expired)
                      ? Column(
                          children: [
                            Text(
                              'Esta invitación ya fue respondida (${vm.match!.status.name.toLowerCase()}).',
                              textAlign: TextAlign.center,
                              style: AppFonts.body().copyWith(
                                color: context.palette.contrast.withValues(alpha: 0.6),
                              ),
                            ),
                            const SizedBox(height: 12),
                            CustomButton(
                              label: 'Cerrar',
                              color: AppColors.accent3,
                              onClick: () => Navigator.pop(context),
                            ),
                          ],
                        )
                      : Column(
                          children: [
                            CustomButton(
                              label: 'Accept Invitation',
                              color: AppColors.accent2,
                              onClick: _accept,
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: TextButton(
                                onPressed: _decline,
                                child: Text(
                                  'Decline',
                                  style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                                    fontSize: 15,
                                    color: context.palette.contrast.withValues(alpha: 0.4),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Shown without connection when the invitation was not saved on the device
  Widget _buildUnavailable(MatchInvitationViewModel vm) {
    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          children: [
            const OfflineBanner(message: 'Sin conexión · esta invitación no está guardada'),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.wifi_off_rounded, size: 56, color: context.palette.contrast.withValues(alpha: 0.25)),
                    const SizedBox(height: 16),
                    Text(
                      'No pudimos cargar la invitación sin conexión. Cuando vuelva la red, toca Reintentar.',
                      textAlign: TextAlign.center,
                      style: AppFonts.body().copyWith(color: context.palette.contrast.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 24),
                    CustomButton(label: 'Reintentar', color: AppColors.accent3, onClick: vm.retry),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Card with the photo, name and career of the user who sent the match
  Widget _buildUserCard(User user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.contrast.withValues(alpha: 0.04),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: context.palette.contrast.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          AvatarWidget(
            url: user.avatarUrl,
            name: user.name,
            size: 70,
            border: Border.all(color: AppColors.accent3.withValues(alpha: 0.2), width: 3),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.name,
                  style: AppFonts.display(weight: FontWeight.w900).copyWith(
                    fontSize: 20,
                    color: context.palette.contrast,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  user.career,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.subtitle(weight: FontWeight.w600).copyWith(
                    fontSize: 13,
                    color: context.palette.contrast.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
