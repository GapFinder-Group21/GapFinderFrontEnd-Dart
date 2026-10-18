import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/interests_view_model.dart';

/// Onboarding step where the user picks their interests (used to find better matches).
class InterestsView extends StatelessWidget {
  const InterestsView({super.key});

  // Saves the selected interests and moves to the schedule setup
  Future<void> _handleContinue(BuildContext context) async {
    final vm = context.read<InterestsViewModel>();
    final ok = await vm.save();
    if (!context.mounted) return;

    if (ok) {
      Navigator.pushReplacementNamed(context, AppRoutes.scheduleSetup);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vm.errorMessage ?? '')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<InterestsViewModel>();

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: const CustomTopBar(
        title: 'GAP FINDER',
        subtitle: 'Profile Setup',
      ),
      body: Builder(
        builder: (context) {
          if (vm.isLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (vm.loadError != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  'Error loading interests: ${vm.loadError}',
                  textAlign: TextAlign.center,
                  style: AppFonts.body().copyWith(color: context.palette.contrast.withOpacity(0.6)),
                ),
              ),
            );
          }

          final interests = vm.interests;

          return Column(
            children: [
              // List of interests the user can tap
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'What are you into?',
                        style: AppFonts.display(weight: FontWeight.w800).copyWith(
                          fontSize: 22,
                          color: context.palette.contrast,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Select all that apply — we'll use this for matching",
                        style: AppFonts.subtitle().copyWith(
                          fontSize: 14,
                          color: context.palette.contrast.withOpacity(0.55),
                        ),
                      ),
                      const SizedBox(height: 28),
                      // One chip per interest; selected ones are highlighted
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: interests.map((interest) {
                          final bool isSelected = vm.isSelected(interest.id);

                          return GestureDetector(
                            onTap: () => vm.toggleInterest(interest.id),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.accent1 : context.palette.surface,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(
                                  width: 1.5,
                                  color: isSelected ? AppColors.accent1 : context.palette.contrast.withOpacity(0.18),
                                ),
                              ),
                              child: Text(
                                interest.name,
                                style: AppFonts.body(
                                  weight: isSelected ? FontWeight.w700 : FontWeight.w400,
                                ).copyWith(
                                  fontSize: 13,
                                  color: isSelected ? Colors.white : context.palette.contrast,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(24),
                child: vm.isSaving
                    ? const CircularProgressIndicator()
                    : CustomButton(
                        label: 'Continue',
                        onClick: () => _handleContinue(context),
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}
