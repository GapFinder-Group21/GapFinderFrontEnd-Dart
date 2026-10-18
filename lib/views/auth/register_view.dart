import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/core/constants/careers.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/register_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_input.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:gapfinderfrontend_dart/models/enums/effort_type_enum.dart';

/// Sign up form: name, email, career, semester, phone, preferred effort and password.
class RegisterView extends StatefulWidget {
  const RegisterView({super.key});

  @override
  State<RegisterView> createState() => _RegisterViewState();
}

class _RegisterViewState extends State<RegisterView> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _semesterController = TextEditingController();
  final _phoneController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _semesterController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  // Sends the fields to the ViewModel and goes on when the account is created
  Future<void> _handleRegister() async {
    final vm = context.read<RegisterViewModel>();
    final ok = await vm.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim().toLowerCase(),
      password: _passwordController.text,
      confirmPassword: _confirmPasswordController.text,
      semesterText: _semesterController.text.trim(),
      phone: _phoneController.text.trim(),
    );
    if (!mounted) return;

    if (ok) {
      Navigator.pushReplacementNamed(
        context,
        AppRoutes.locationPermission,
        arguments: {'fromOnboarding': true},
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(vm.errorMessage ?? '')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RegisterViewModel>();

    return Scaffold(
      backgroundColor: context.palette.background,
      appBar: const TopBar(
        title: 'GAP FINDER',
        subtitle: 'Create Account',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Create Account',
              style: AppFonts.display(weight: FontWeight.w800).copyWith(
                fontSize: 22,
                color: context.palette.contrast,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Join the campus network',
              style: AppFonts.subtitle(weight: FontWeight.w400).copyWith(
                fontSize: 14,
                color: context.palette.contrast.withValues(alpha: 0.55),
              ),
            ),
            const SizedBox(height: 24),

            // Full Name
            CustomInput(
              placeholder: 'Full Name',
              controller: _nameController,
            ),
            const SizedBox(height: 14),

            // Email
            CustomInput(
              placeholder: 'Email',
              keyboardType: TextInputType.emailAddress,
              controller: _emailController,
            ),
            const SizedBox(height: 14),

            // Career selector
            Text(
              'Career',
              style: AppFonts.subtitle(weight: FontWeight.w600).copyWith(
                fontSize: 14,
                color: context.palette.contrast,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: vm.selectedCareer,
              isExpanded: true,
              dropdownColor: context.palette.background,
              style: AppFonts.subtitle(weight: FontWeight.w400).copyWith(
                color: context.palette.contrast,
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: careers.map((String career) {
                return DropdownMenuItem<String>(
                  value: career,
                  child: Text(
                    career,
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              }).toList(),
              onChanged: vm.selectCareer,
            ),
            const SizedBox(height: 14),

            // Semester (1 to 12)
            CustomInput(
              placeholder: 'Semester (1 - 12)',
              keyboardType: TextInputType.number,
              controller: _semesterController,
            ),
            const SizedBox(height: 14),

            // Phone Number
            CustomInput(
              placeholder: 'Phone Number',
              keyboardType: TextInputType.phone,
              controller: _phoneController,
            ),
            const SizedBox(height: 14),

            // Preferred Effort (LOW, MEDIUM, HIGH)
            Text(
              'Preferred Effort',
              style: AppFonts.subtitle(weight: FontWeight.w600).copyWith(
                fontSize: 14,
                color: context.palette.contrast,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<EffortTypeEnum>(
              value: vm.selectedEffort,
              isExpanded: true,
              dropdownColor: context.palette.background,
              style: AppFonts.subtitle(weight: FontWeight.w400).copyWith(
                color: context.palette.contrast,
              ),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: EffortTypeEnum.values.map((effort) {
                return DropdownMenuItem(
                  value: effort,
                  child: Text(effort.name),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  vm.selectEffort(value);
                }
              },
            ),
            const SizedBox(height: 14),

            // Password (min 8 chars)
            CustomInput(
              placeholder: 'Password (min 8 characters)',
              obscureText: true,
              controller: _passwordController,
            ),
            const SizedBox(height: 14),

            // Confirm Password
            CustomInput(
              placeholder: 'Confirm Password',
              obscureText: true,
              controller: _confirmPasswordController,
            ),

            const SizedBox(height: 28),

            // Submit Button
            vm.isLoading
                ? const Center(child: CircularProgressIndicator())
                : CustomButton(
              label: 'Create Account',
              onClick: _handleRegister,
            ),

            const SizedBox(height: 14),

            // Log In Redirect
            SizedBox(
              width: double.infinity,
              child: TextButton(
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
                    color: context.palette.contrast.withValues(alpha: 0.55),
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
