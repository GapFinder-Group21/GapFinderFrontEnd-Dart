import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';

class CustomInput extends StatelessWidget {
  final String placeholder;
  final TextInputType keyboardType;
  final bool obscureText;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final String? errorText; // red text under the field
  final int? maxLength; // max chars
  final List<TextInputFormatter>? inputFormatters; // allowed chars

  const CustomInput({
    super.key,
    required this.placeholder,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.controller,
    this.onChanged,
    this.errorText,
    this.maxLength,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    final errorColor = Theme.of(context).colorScheme.error;
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      inputFormatters: [
        ...?inputFormatters,
        // Limits length without the "0/50" counter
        if (maxLength != null) LengthLimitingTextInputFormatter(maxLength),
      ],
      style: AppFonts.body(weight: FontWeight.w400).copyWith(
        fontSize: 15,
        color: context.palette.contrast,
      ),
      decoration: InputDecoration(
        hintText: placeholder,
        hintStyle: AppFonts.body(weight: FontWeight.w400).copyWith(
          fontSize: 15,
          color: context.palette.contrast.withValues(alpha: 0.4),
        ),
        errorText: errorText,
        errorMaxLines: 2,
        filled: true,
        fillColor: context.palette.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
            color: context.palette.contrast.withValues(alpha: 0.15),
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
        // Keep rounded style when there is an error
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: errorColor, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: errorColor, width: 1.5),
        ),
      ),
    );
  }
}
