import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';

class CustomInput extends StatelessWidget {
  final String placeholder;
  final TextInputType keyboardType;
  final bool obscureText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;

  const CustomInput({
    super.key,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      style: AppFonts.body(weight: FontWeight.w400).copyWith(
        fontSize: 15,
        color: AppColors.contrast,
      ),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: AppFonts.body(weight: FontWeight.w400).copyWith(
          fontSize: 15,
          color: AppColors.contrast.withValues(alpha: 0.4),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: AppColors.contrast.withValues(alpha: 0.15),
            width: 1.5,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
            color: AppColors.accent1,
            width: 1.5,
          ),
        ),
      ),
    );
  }
}
