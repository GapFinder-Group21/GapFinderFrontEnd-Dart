// First screen of the app: options to sign up or log in.
import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/token_storage.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.contrast,
      body: SafeArea(
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
                    Navigator.pushNamed(context, '/register');
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
                  Navigator.pushNamed(context, '/login');
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
      ),
    );
  }
}
