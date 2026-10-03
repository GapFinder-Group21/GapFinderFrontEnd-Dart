import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';

class CustomButton extends StatelessWidget {
  final String label;
  final VoidCallback? onClick;
  final Color color;
  final Color textColor;
  final bool outline;
  final bool small;

  const CustomButton({
    super.key,
    required this.label,
    this.onClick,
    this.color = AppColors.accent1,
    this.textColor = Colors.white,
    this.outline = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onClick,
        style: ElevatedButton.styleFrom(
          backgroundColor: outline ? Colors.transparent : color,
          foregroundColor: outline ? color : textColor,
          padding: EdgeInsets.symmetric(vertical: small ? 10 : 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: outline ? BorderSide(color: color, width: 2) : BorderSide.none,
          ),
          elevation: 0,
         ),
        child: Text(
          label,
          style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
            fontSize: small ? 14 : 16,
            letterSpacing: 0.3,
            color: outline ? color : textColor,
          ),
        ),
      ),
    );
  }
}
