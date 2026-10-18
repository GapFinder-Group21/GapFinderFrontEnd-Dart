import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/google_calendar_view_model.dart';

/// Imports the user's class schedule from Google Calendar.
/// Shows three states: importing, success or error.
class GoogleCalendarView extends StatelessWidget {
  const GoogleCalendarView({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GoogleCalendarViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CustomTopBar(
        title: 'Google Calendar',
        showBack: true,
      ),
      body: SafeArea(
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Spacer(),
              // State 1: importing (spinner)
              if (vm.phase == GoogleImportPhase.connecting) ...[
                SizedBox(
                  width: 64,
                  height: 64,
                  child: CircularProgressIndicator(
                    strokeWidth: 3.5,
                    valueColor: AlwaysStoppedAnimation<Color>(AppColors.accent3),
                  ),
                ),
                const SizedBox(height: 36),
                Text(
                  'Connecting to Google...',
                  textAlign: TextAlign.center,
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 20,
                    color: AppColors.contrast,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Importing your calendar events',
                  textAlign: TextAlign.center,
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: 14,
                    color: AppColors.contrast.withOpacity(0.5),
                  ),
                ),
              // State 2: import finished
              ] else if (vm.phase == GoogleImportPhase.success) ...[
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.accent3,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.check_rounded, color: Colors.white, size: 38),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Calendar connected!',
                  textAlign: TextAlign.center,
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 20,
                    color: AppColors.contrast,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Your Google Calendar events have been imported successfully.',
                  textAlign: TextAlign.center,
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: 14,
                    color: AppColors.contrast.withOpacity(0.55),
                  ),
                ),
              // State 3: import failed
              ] else ...[
                Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.accent1,
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.close_rounded, color: Colors.white, size: 38),
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'Something went wrong',
                  textAlign: TextAlign.center,
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 20,
                    color: AppColors.contrast,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  vm.errorMessage ?? 'We couldn\'t import your calendar. Try again.',
                  textAlign: TextAlign.center,
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: 14,
                    color: AppColors.contrast.withOpacity(0.55),
                  ),
                ),
              ],
              const Spacer(),
              // Success: go to the home screen
              if (vm.phase == GoogleImportPhase.success)
                CustomButton(
                  label: 'Continue',
                  color: AppColors.accent3,
                  onClick: () {
                    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (route) => false);
                  },
                ),
              // Error: let the user try again
              if (vm.phase == GoogleImportPhase.error)
                CustomButton(
                  label: 'Try Again',
                  color: AppColors.accent1,
                  onClick: vm.importSchedule,
                ),
            ],
          ),
        ),
      ),
    );
  }
}