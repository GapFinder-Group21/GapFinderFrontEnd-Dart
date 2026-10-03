import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/widgets/custom_top_bar.dart';
import '../../core/widgets/schedule_option_card.dart';

/// Onboarding step where the user chooses how to add their classes (Google Calendar).
class ScheduleSetupScreen extends StatelessWidget {
  const ScheduleSetupScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CustomTopBar(
        title: 'GAP FINDER',
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Set up your schedule',
              style: AppFonts.display(weight: FontWeight.w800).copyWith(
                fontSize: 22,
                color: AppColors.contrast,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Import your classes from Google Calendar',
              style: AppFonts.subtitle().copyWith(
                fontSize: 14,
                color: AppColors.contrast.withOpacity(0.55),
              ),
            ),
            const SizedBox(height: 32),

            // Google Calendar Option
            ScheduleOptionCard(
              title: 'Connect Google Calendar',
              subtitle: 'Import from your personal calendar',
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
                Navigator.pushNamed(context, '/google-connect');
              },
            ),

          ],
        ),
      ),
    );
  }
}