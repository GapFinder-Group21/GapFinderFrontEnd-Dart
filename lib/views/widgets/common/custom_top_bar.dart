import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';

class CustomTopBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final String? subtitle;
  final bool showBack;
  final VoidCallback? onBack;
  // Optional widget before the title (for example the friend's avatar in the chat)
  final Widget? leading;
  // Space after the back arrow and between the title and the subtitle (the chat uses 14 and 0)
  final double backGap;
  final double subtitleGap;

  const CustomTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.showBack = true,
    this.onBack,
    this.leading,
    this.backGap = 12,
    this.subtitleGap = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.contrast,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (showBack) ...[
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: AppColors.background,
                  size: 20,
                ),
                onPressed: onBack ?? () => Navigator.of(context).pop(),
              ),
              SizedBox(width: backGap),
            ],
            if (leading != null) ...[
              leading!,
              const SizedBox(width: 10),
            ],
            // Flexible: a long title wraps instead of overflowing
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: AppFonts.display(weight: FontWeight.w800).copyWith(
                      fontSize: 16,
                      color: AppColors.background,
                      letterSpacing: 0.5,
                    ),
                  ),
                  if (subtitle != null) ...[
                    SizedBox(height: subtitleGap),
                    Text(
                      subtitle!,
                      style: AppFonts.subtitle().copyWith(
                        fontSize: 12,
                        color: AppColors.background.withOpacity(0.65),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(72.0);
}
