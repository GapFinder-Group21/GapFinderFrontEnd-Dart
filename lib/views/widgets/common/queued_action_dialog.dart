import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';

// Tells the user their action was saved offline and will be sent when the internet comes back
Future<void> showQueuedActionDialog(BuildContext context, {required String title, required String message}) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.cloud_upload_outlined, color: AppColors.accent2, size: 36),
      title: Text(title, style: AppFonts.display(weight: FontWeight.w800)),
      content: Text(message, style: AppFonts.body()),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Entendido'),
        ),
      ],
    ),
  );
}
