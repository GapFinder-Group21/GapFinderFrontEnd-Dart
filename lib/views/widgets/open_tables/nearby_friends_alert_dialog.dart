import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/avatar_widget.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';

class NearbyFriendsAlertDialog extends StatelessWidget {
  final String buildingName;
  final List<User> friends;

  const NearbyFriendsAlertDialog({
    super.key,
    required this.buildingName,
    required this.friends,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: context.palette.surface,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.accent2.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.people_rounded, color: AppColors.accent2, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Friends Nearby!',
                        style: AppFonts.display(weight: FontWeight.w900).copyWith(
                          fontSize: 18,
                          color: context.palette.contrast,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'You entered $buildingName',
                        style: AppFonts.body().copyWith(
                          fontSize: 13,
                          color: context.palette.contrast.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Text(
              '${friends.length} friends are in this building right now:',
              style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                fontSize: 13,
                color: context.palette.contrast,
              ),
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 250),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: friends.length,
                itemBuilder: (context, index) {
                  final friend = friends[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: context.palette.background,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: context.palette.contrast.withValues(alpha: 0.08)),
                    ),
                    child: Row(
                      children: [
                        AvatarWidget(url: friend.avatarUrl, name: friend.name, size: 40),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                friend.name,
                                style: AppFonts.display(weight: FontWeight.w800).copyWith(
                                  fontSize: 14,
                                  color: context.palette.contrast,
                                ),
                              ),
                              Text(
                                '${friend.career} · Sem ${friend.semester ?? 1}',
                                style: AppFonts.body().copyWith(
                                  fontSize: 11,
                                  color: context.palette.contrast.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            CustomButton(
              label: 'Awesome',
              color: AppColors.accent2,
              onClick: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}
