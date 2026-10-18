import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/login_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_input.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';

/// Log in with email and password.
class LoginView extends StatefulWidget {
  const LoginView({super.key});

  @override
  State<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends State<LoginView> {
  // Text field controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Validates the fields and logs in
  Future<void> _handleLogin() async {
    final vm = context.read<LoginViewModel>();
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final validationError = vm.validate(email, password);
    if (validationError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(validationError)),
      );
      return;
    }

    final ok = await vm.login(email, password);
    if (!mounted) return;

    if (ok) {
      // Go to home and remove the previous screens from the history
      Navigator.pushNamedAndRemoveUntil(context, AppRoutes.home, (route) => false);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(vm.errorMessage ?? ''),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<LoginViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const TopBar(
        title: 'GAP FINDER',
        subtitle: 'Log In',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title
            Text(
              'Welcome back',
              style: AppFonts.display(weight: FontWeight.w800).copyWith(
                fontSize: 22,
                color: AppColors.contrast,
              ),
            ),

            const SizedBox(height: 6),

            // Subtitle
            Text(
              'Sign in to your account',
              style: AppFonts.subtitle(weight: FontWeight.w400).copyWith(
                fontSize: 14,
                color: AppColors.contrast.withValues(alpha: 0.55),
              ),
            ),

            const SizedBox(height: 24),

            // Email and password fields
            CustomInput(
              placeholder: 'Email',
              controller: _emailController,
            ),
            const SizedBox(height: 14),

            CustomInput(
              placeholder: 'Password',
              obscureText: true,
              controller: _passwordController,
            ),

            const SizedBox(height: 28),

            // Log In button (shows a spinner while loading)
            vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : CustomButton(
              label: 'Log In',
              onClick: _handleLogin,
            ),

            const SizedBox(height: 14),

            // Link to the sign up screen
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.register);
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  "Don't have an account? Register",
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: 14,
                    color: AppColors.contrast.withValues(alpha: 0.55),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
