import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/schedule_setup_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/schedule_option_card.dart';

/// Onboarding step where the user chooses how to add their classes (Google Calendar).
class ScheduleSetupView extends StatelessWidget {
  const ScheduleSetupView({super.key});

  // Leaves the schedule for later and enters the app
  void _continueLater(BuildContext context) {
    context.read<ScheduleSetupViewModel>().continueLater();
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ScheduleSetupViewModel>();

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: CustomTopBar(
        title: 'GAP FINDER',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: Column(
        children: [
          if (vm.isOffline) const OfflineBanner(message: ScheduleSetupViewModel.offlineBanner),
          Expanded(child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set up your schedule',
              style: AppFonts.display(weight: FontWeight.w800).copyWith(
                fontSize: 22,
                color: context.palette.contrast,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Import your classes from Google Calendar',
              style: AppFonts.subtitle().copyWith(
                fontSize: 14,
                color: context.palette.contrast.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 32),

            // Google Calendar Option
            ScheduleOptionCard(
              title: 'Connect Google Calendar',
              subtitle: vm.canConnectGoogle
                  ? 'Import from your personal calendar'
                  : ScheduleSetupViewModel.googleOfflineText,
              enabled: vm.canConnectGoogle,
              icon: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppColors.accent1,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(
                    Icons.calendar_today_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
              ),
              onTap: () {
                Navigator.pushNamed(context, AppRoutes.googleConnect);
              },
            ),

            // Without internet the user can set the schedule up later
            if (vm.isOffline) ...[
              const SizedBox(height: 20),
              CustomButton(
                label: 'Continuar más tarde',
                outline: true,
                onClick: () => _continueLater(context),
              ),
            ],
          ],
        ),
      )),
        ],
      ),
    );
  }
}