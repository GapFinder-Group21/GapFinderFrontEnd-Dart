import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';

/// Thin strip that tells the user the data on screen may be old because there is no connection.
/// Example: OfflineBanner(message: 'Sin conexión', lastUpdated: vm.lastUpdated)
class OfflineBanner extends StatelessWidget {
  final String message;
  final DateTime? lastUpdated;

  const OfflineBanner({super.key, required this.message, this.lastUpdated});

  // HH:mm of the last update
  String _time(DateTime date) {
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  @override
  Widget build(BuildContext context) {
    final updated = lastUpdated;
    final text = updated == null ? message : '$message · actualizado a las ${_time(updated)}';

    final palette = context.palette;

    return Container(
      width: double.infinity,
      // Opaque, so the text reads well on any screen (also on the dark welcome screen)
      color: Color.alphaBlend(AppColors.accent1.withValues(alpha: 0.14), palette.surface),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 1),
            child: Icon(Icons.wifi_off_rounded, size: 14, color: AppColors.accent1),
          ),
          const SizedBox(width: 8),
          // Wraps to as many lines as needed: the whole message is always shown
          Expanded(
            child: Text(
              text,
              softWrap: true,
              style: AppFonts.body(weight: FontWeight.w700).copyWith(
                fontSize: 12,
                height: 1.3,
                color: palette.contrast,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
