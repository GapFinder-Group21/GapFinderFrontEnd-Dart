// First screen of the app: options to sign up or log in.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/viewmodels/welcome/welcome_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';

// It brings its own ViewModel, so the route and the session gate can keep using it as a const
class WelcomeView extends StatelessWidget {
  const WelcomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => WelcomeViewModel()..init(),
      child: const _WelcomeBody(),
    );
  }
}

class _WelcomeBody extends StatelessWidget {
  const _WelcomeBody();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<WelcomeViewModel>();

    return Scaffold(
      backgroundColor: AppColors.contrast,
      body: SafeArea(
        child: Column(
          children: [
            // Works without internet; only tells the user why sign up and log in must wait
            if (vm.showOfflineNotice)
              const OfflineBanner(
                message: 'Sin conexión: podrás crear tu cuenta o entrar cuando vuelva internet',
              ),
            Expanded(child: _buildContent(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo
              ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Image.asset(
                  'assets/images/logo_gap_finder.png',
                  width: 110,
                  height: 110,
                  fit: BoxFit.contain,
                ),
              ),

              const SizedBox(height: 16),

              // App name
              Text(
                'GAP FINDER',
                style: AppFonts.display(weight: FontWeight.w900).copyWith(
                  fontSize: 34,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),

              const SizedBox(height: 4),

              // Subtitle
              Text(
                'Make your gaps count.',
                style: AppFonts.subtitle(weight: FontWeight.w400).copyWith(
                  fontSize: 16,
                  color: Colors.white.withValues(alpha: 0.65),
                  letterSpacing: 0.5,
                ),
              ),

              const SizedBox(height: 64),

              // Get Started button: goes to sign up
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.register);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent1,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    elevation: 0,
                  ),
                  child: Text(
                    'Get Started',
                    style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                      fontSize: 16,
                      letterSpacing: 0.3,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Link to log in for users who already have an account
              TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.login);
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'Already have an account? Log In',
                  style: AppFonts.subtitle(weight: FontWeight.w400).copyWith(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}
