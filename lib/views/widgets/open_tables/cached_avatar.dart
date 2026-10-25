import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/avatar_widget.dart';

// Avatar of a table creator whose image is kept on disk by cached_network_image, so it still shows
// without connection after it was loaded once. While it loads, a spinner; with no URL or if it
// fails, the same initials avatar as AvatarWidget.
class CachedAvatar extends StatelessWidget {
  final String? url;
  final String? name;
  final double size;

  const CachedAvatar({super.key, this.url, this.name, this.size = 48});

  @override
  Widget build(BuildContext context) {
    final resolved = AvatarWidget.resolveUrl(url);
    final initials = AvatarWidget(name: name, size: size);
    if (resolved == null) return initials;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppColors.contrast.withValues(alpha: 0.12), width: 2),
        color: context.palette.background,
      ),
      clipBehavior: Clip.antiAlias,
      child: CachedNetworkImage(
        imageUrl: resolved,
        fit: BoxFit.cover,
        width: size,
        height: size,
        placeholder: (_, _) => Center(
          child: SizedBox(
            width: size * 0.4,
            height: size * 0.4,
            child: const CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
        errorWidget: (_, _, _) => initials,
      ),
    );
  }
}
