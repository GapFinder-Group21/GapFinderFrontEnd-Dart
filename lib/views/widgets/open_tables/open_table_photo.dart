import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/avatar_widget.dart';

// Photo of an open table. Draws nothing when the table has no photo
class OpenTablePhoto extends StatelessWidget {
  final String? url;
  final double height;
  final BorderRadius borderRadius;

  const OpenTablePhoto({
    super.key,
    required this.url,
    this.height = 160,
    this.borderRadius = BorderRadius.zero,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = AvatarWidget.resolveUrl(url);
    if (resolved == null) return const SizedBox.shrink();

    return ClipRRect(
      borderRadius: borderRadius,
      child: Image.network(
        resolved,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) => progress == null
            ? child
            : SizedBox(
                height: height,
                child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
        // If the photo cannot load, a camera icon keeps the space
        errorBuilder: (_, _, _) => Container(
          height: height,
          width: double.infinity,
          color: AppColors.background,
          child: Icon(
            Icons.photo_camera_rounded,
            color: AppColors.contrast.withValues(alpha: 0.25),
            size: 32,
          ),
        ),
      ),
    );
  }
}
