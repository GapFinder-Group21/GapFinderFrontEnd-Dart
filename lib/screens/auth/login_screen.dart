import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/widgets/top_bar.dart';
import '../../core/widgets/custom_input.dart';
import '../../core/widgets/custom_button.dart';
import '../../services/auth_service.dart';

/// Log in with email and password.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Text field controllers
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Validates the fields and logs in - POST /auth/login
  Future<void> _handleLogin() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all fields')),
      );
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Logs in and saves the tokens on the device
      await _authService.login(email, password);

      if (!mounted) return;

      // Go to home and remove the previous screens from the history
      Navigator.pushNamedAndRemoveUntil(context, '/home', (route) => false);
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: Colors.redAccent,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
            _isLoading
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
                  Navigator.pushNamed(context, '/register');
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