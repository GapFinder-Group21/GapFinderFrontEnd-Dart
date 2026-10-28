import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';

class ScheduleOptionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget icon;
  final VoidCallback onTap;
  // False when the option cannot be used now (for example without internet)
  final bool enabled;

  const ScheduleOptionCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.5,
      child: Material(
      color: context.palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: context.palette.contrast.withOpacity(0.15),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              icon,
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppFonts.display(weight: FontWeight.w700).copyWith(
                        fontSize: 15,
                        color: context.palette.contrast,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: AppFonts.body().copyWith(
                        fontSize: 12,
                        color: context.palette.contrast.withOpacity(0.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
