import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/location_permission_view_model.dart';

/// Explains why the app needs the location and asks the user for permission.
class LocationPermissionView extends StatelessWidget {
  const LocationPermissionView({super.key});

  // During sign up go to the interests screen; otherwise go back (or to home)
  void _navigateForward(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final bool fromOnboarding = args?['fromOnboarding'] ?? false;

    if (fromOnboarding) {
      Navigator.pushReplacementNamed(context, AppRoutes.interests);
    } else {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.home);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Location icon
              Container(
                width: 80,
                height: 80,
                decoration: const BoxDecoration(
                  color: AppColors.accent2,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.location_on_rounded,
                  size: 36,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),

              // Title
              Text(
                'Enable Location',
                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                  fontSize: 22,
                  color: AppColors.contrast,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Why we need the location
              Text(
                'GAP FINDER uses your location to identify your campus area and show Open Tables.',
                style: AppFonts.body().copyWith(
                  fontSize: 15,
                  color: AppColors.contrast.withValues(alpha: 0.6),
                  height: 1.55,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),

              // Main button: ask for the permission (or open settings if it was denied forever)
              const SizedBox(height: 8),
              CustomButton(
                label: 'Allow Location',
                color: AppColors.accent2,
                onClick: () async {
                  final vm = context.read<LocationPermissionViewModel>();
                  final result = await vm.requestPermission();

                  if (result == LocationPermissionResult.granted) {
                    if (context.mounted) {
                      _navigateForward(context);
                    }
                  } else if (result == LocationPermissionResult.deniedForever) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Permission permanently denied. Please enable it in settings.')),
                      );
                      vm.openAppSettings();
                    }
                  }
                },
              ),

              // Secondary button: skip for now
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'You can use the app, but some features won\'t be available without location.',
                          style: AppFonts.body().copyWith(fontSize: 13, color: Colors.white),
                        ),
                        backgroundColor: AppColors.contrast.withValues(alpha: 0.8),
                        duration: const Duration(seconds: 4),
                      ),
                    );
                    _navigateForward(context);
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                  ),
                  child: Text(
                    'Skip for now',
                    style: AppFonts.body().copyWith(
                      fontSize: 14,
                      color: AppColors.contrast.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
