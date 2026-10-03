import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/constants/careers.dart';
import '../../core/widgets/top_bar.dart';
import '../../services/auth_service.dart';
import '../../core/widgets/custom_input.dart';
import '../../core/widgets/custom_button.dart';
import '../../models/effort_type_enum.dart';

/// Sign up form: name, email, career, semester, phone, preferred effort and password.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _semesterController = TextEditingController();
  final _phoneController = TextEditingController();

  String? _selectedCareer = careers.first;
  EffortTypeEnum _selectedEffort = EffortTypeEnum.MEDIUM;
  bool _isLoading = false;
  final _authService = AuthService();

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

  // Validates every field and creates the account - POST /auth/register
  Future<void> _handleRegister() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim().toLowerCase();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;
    final semesterText = _semesterController.text.trim();
    final phone = _phoneController.text.trim();

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa tu nombre')),
      );
      return;
    }

    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa un correo electrónico válido')),
      );
      return;
    }

    if (password.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La contraseña debe tener al menos 8 caracteres')),
      );
      return;
    }

    if (password != confirmPassword) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Las contraseñas no coinciden')),
      );
      return;
    }

    final semester = int.tryParse(semesterText);
    if (semester == null || semester < 1 || semester > 12) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El semestre debe ser un número entre 1 y 12')),
      );
      return;
    }

    if (_selectedCareer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor selecciona una carrera')),
      );
      return;
    }

    if (phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor ingresa tu número de teléfono')),
      );
      return;
    }

    // Same rule as the backend: optional + and 7 to 15 digits
    final normalizedPhone = phone.replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^\+?\d{7,15}$').hasMatch(normalizedPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('El teléfono debe tener de 7 a 15 dígitos (puede empezar con +)')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.register(
        name: name,
        email: email,
        password: password,
        career: _selectedCareer!,
        semester: semester,
        preferredEffort: _selectedEffort,
        phoneNumber: normalizedPhone,
      );

      if (mounted) {
        Navigator.pushReplacementNamed(
          context, 
          '/location-permission',
          arguments: {'fromOnboarding': true},
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString().replaceAll('Exception: ', ''))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                color: AppColors.contrast,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Join the campus network',
              style: AppFonts.subtitle(weight: FontWeight.w400).copyWith(
                fontSize: 14,
                color: AppColors.contrast.withValues(alpha: 0.55),
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
                color: AppColors.contrast,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedCareer,
              isExpanded: true,
              dropdownColor: AppColors.background,
              style: AppFonts.subtitle(weight: FontWeight.w400).copyWith(
                color: AppColors.contrast,
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
              onChanged: (value) {
                setState(() => _selectedCareer = value);
              },
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
                color: AppColors.contrast,
              ),
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<EffortTypeEnum>(
              value: _selectedEffort,
              isExpanded: true,
              dropdownColor: AppColors.background,
              style: AppFonts.subtitle(weight: FontWeight.w400).copyWith(
                color: AppColors.contrast,
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
                  setState(() => _selectedEffort = value);
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
            _isLoading
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
