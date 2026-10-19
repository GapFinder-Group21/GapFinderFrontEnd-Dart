import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
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
      // Memory and disk cache: a photo seen once is still shown without connection
      child: CachedNetworkImage(
        imageUrl: resolved,
        height: height,
        width: double.infinity,
        fit: BoxFit.cover,
        // While the photo loads
        placeholder: (context, _) => SizedBox(
          height: height,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        // If the photo cannot load (and it was never cached), a camera icon keeps the space
        errorWidget: (context, _, _) => Container(
          height: height,
          width: double.infinity,
          color: context.palette.background,
          child: Icon(
            Icons.photo_camera_rounded,
            color: context.palette.contrast.withValues(alpha: 0.25),
            size: 32,
          ),
        ),
      ),
    );
  }
}
