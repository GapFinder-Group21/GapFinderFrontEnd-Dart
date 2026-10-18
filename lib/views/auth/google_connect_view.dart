import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/google_connect_view_model.dart';

/// Opens the Google sign-in page in the browser so the user can link their Google Calendar.
class GoogleConnectView extends StatelessWidget {
  const GoogleConnectView({super.key});

  // After signing in with Google, go to the import screen
  void _continueToImport(BuildContext context) {
    Navigator.pushReplacementNamed(context, AppRoutes.googleCalendar);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<GoogleConnectViewModel>();

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
              Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.accent3,
                  shape: BoxShape.circle,
                ),
                child: const Center(
                  child: Icon(
                    Icons.calendar_month_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Connect Google Calendar',
                textAlign: TextAlign.center,
                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                  fontSize: 20,
                  color: AppColors.contrast,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                vm.opened
                    ? 'Finish signing in with your Google account in the browser, then come back and tap Continue.'
                    : 'You\'ll be taken to Google to sign in and authorize access to your calendar.',
                textAlign: TextAlign.center,
                style: AppFonts.body(weight: FontWeight.w400).copyWith(
                  fontSize: 14,
                  color: AppColors.contrast.withOpacity(0.55),
                ),
              ),
              // Error message, if opening Google failed
              if (vm.error != null) ...[
                const SizedBox(height: 16),
                Text(
                  vm.error!,
                  textAlign: TextAlign.center,
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: 13,
                    color: AppColors.accent1,
                  ),
                ),
              ],
              const SizedBox(height: 40),
              // Button: open Google first, then continue to the import
              if (vm.loading)
                const CircularProgressIndicator()
              else if (!vm.opened)
                CustomButton(
                  label: 'Continue with Google',
                  color: AppColors.accent3,
                  onClick: vm.openGoogleAuth,
                )
              else ...[
                  CustomButton(
                    label: 'Continue',
                    color: AppColors.accent3,
                    onClick: () => _continueToImport(context),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: vm.openGoogleAuth,
                    child: Text(
                      'Open Google sign-in again',
                      style: AppFonts.body(weight: FontWeight.w400).copyWith(
                        fontSize: 13,
                        color: AppColors.contrast.withOpacity(0.5),
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}