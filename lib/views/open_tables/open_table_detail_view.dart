import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/open_table_detail_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/avatar_widget.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_top_bar.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/custom_button.dart';
import 'package:gapfinderfrontend_dart/views/widgets/open_tables/open_table_photo.dart';

/// Details of one open table: creator, activity, building, time left and participants.
/// The user can join the table or leave it.
class OpenTableDetailView extends StatefulWidget {
  const OpenTableDetailView({super.key});

  @override
  State<OpenTableDetailView> createState() => _OpenTableDetailViewState();
}

class _OpenTableDetailViewState extends State<OpenTableDetailView> {
  // ViewModel for callbacks and helper builders (build() watches it)
  OpenTableDetailViewModel get _vm => context.read<OpenTableDetailViewModel>();

  // Join the table and show the result
  Future<void> _handleJoin() async {
    if (!_vm.hasUser) return;

    final error = await _vm.join();
    if (!mounted) return;
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Successfully joined the table!'),
          backgroundColor: AppColors.accent2,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  // Asks for confirmation, leaves the table and shows the result
  Future<void> _handleLeave() async {
    if (!_vm.hasUser) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Leave table?', style: AppFonts.display(weight: FontWeight.w800)),
        content: Text('You will no longer be a participant of this table.', style: AppFonts.body()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Leave', style: TextStyle(color: AppColors.accent1)),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final error = await _vm.leave();
    if (!mounted) return;
    if (error == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('You left the table')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OpenTableDetailViewModel>();

    return Builder(
      builder: (context) {
        if (vm.isLoading) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (vm.loadError != null) {
          return Scaffold(
            appBar: const CustomTopBar(title: 'Error', showBack: true),
            body: Center(child: Text('Error: ${vm.loadError}')),
          );
        }

        final table = vm.table!;

        final bool isCreator = vm.isCreator;
        final bool isFull = vm.isFull;

        final remainingMins = vm.remainingMinutes;
        // The back does not allow joining or leaving once the end time has passed
        final bool hasEnded = vm.hasEnded;

        return Scaffold(
          backgroundColor: context.palette.background,
          appBar: const CustomTopBar(
            title: 'Open Table Detail',
            showBack: true,
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Photo taken when the table was created
                      if (table.photoUrl != null) ...[
                        OpenTablePhoto(
                          url: table.photoUrl,
                          height: 200,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        const SizedBox(height: 20),
                      ],

                      _buildCreatorCard(table),

                      const SizedBox(height: 28),

                      Text(
                        'ACTIVITY INFO',
                        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: context.palette.contrast.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildActivityCard(table),

                      const SizedBox(height: 28),

                      Text(
                        'LOGISTICS',
                        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: context.palette.contrast.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          _buildDetailItem(
                            icon: Icons.location_on_rounded,
                            label: 'Location',
                            value: table.building?.name ?? 'Unknown',
                          ),
                          const SizedBox(width: 12),
                          _buildDetailItem(
                            icon: Icons.access_time_filled_rounded,
                            label: 'Ends in',
                            value: hasEnded ? 'Ended' : '$remainingMins min',
                          ),
                        ],
                      ),

                      const SizedBox(height: 28),

                      Text(
                        'PROPOSAL',
                        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: context.palette.contrast.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.palette.surface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: context.palette.contrast.withValues(alpha: 0.08), width: 1.5),
                        ),
                        child: Text(
                          table.description,
                          style: AppFonts.body().copyWith(
                            fontSize: 14,
                            color: context.palette.contrast.withValues(alpha: 0.7),
                            height: 1.5,
                          ),
                        ),
                      ),

                      const SizedBox(height: 32),

                      Text(
                        'PARTICIPANTS (${_vm.participants.length}/${table.maxParticipants})',
                        style: AppFonts.subtitle(weight: FontWeight.w800).copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                          color: context.palette.contrast.withValues(alpha: 0.4),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildParticipantsList(),
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.all(24),
                child: vm.isJoining
                    ? const CircularProgressIndicator()
                    : hasEnded
                        ? CustomButton(
                            label: 'Table ended',
                            color: Colors.grey[400]!,
                            onClick: null,
                          )
                    : vm.isMember
                        ? CustomButton(
                            label: 'Leave Table',
                            color: AppColors.accent1,
                            outline: true,
                            onClick: _handleLeave,
                          )
                    : isCreator
                        ? CustomButton(
                            label: 'You created this table',
                            color: Colors.grey[400]!,
                            onClick: null,
                          )
                        : CustomButton(
                            label: isFull ? 'Table full' : 'Join Table',
                            color: isFull ? Colors.grey[400]! : AppColors.accent3,
                            onClick: isFull ? null : _handleJoin,
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  // Card with the photo and name of the creator
  Widget _buildCreatorCard(OpenTable table) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.palette.contrast.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppColors.contrast.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          AvatarWidget(url: table.creator?.avatarUrl, name: table.creator?.name, size: 56),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Created by',
                  style: AppFonts.body().copyWith(
                    fontSize: 12,
                    color: context.palette.contrast.withValues(alpha: 0.4),
                  ),
                ),
                Text(
                  table.creator?.name ?? 'Unknown User',
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 18,
                    color: context.palette.contrast,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card with the activity, max participants, effort and interest
  Widget _buildActivityCard(OpenTable table) {
    final activityName = table.activity?.name ?? table.title;
    final effortText = table.activity?.effortType != null ? '${table.activity!.effortType.name.toLowerCase()} effort' : '';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.accent2.withValues(alpha: 0.15), width: 1.5),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.accent2.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.rocket_launch_rounded, color: AppColors.accent2, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  activityName,
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: 16,
                    color: context.palette.contrast,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Up to ${table.maxParticipants} participants${effortText.isNotEmpty ? ' · $effortText' : ''}',
                  style: AppFonts.body().copyWith(
                    fontSize: 13,
                    color: context.palette.contrast.withValues(alpha: 0.5),
                  ),
                ),
                if (table.activity?.interest != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent2.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: AppColors.accent2.withValues(alpha: 0.2)),
                    ),
                    child: Text(
                      table.activity!.interest!.name,
                      style: AppFonts.body(weight: FontWeight.w700).copyWith(
                        fontSize: 11,
                        color: AppColors.accent2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Small box with an icon, a label and a value (location, time left)
  Widget _buildDetailItem({required IconData icon, required String label, required String value}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: context.palette.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.palette.contrast.withValues(alpha: 0.06)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppColors.accent1),
                const SizedBox(width: 6),
                Text(
                  label.toUpperCase(),
                  style: AppFonts.subtitle(weight: FontWeight.w700).copyWith(
                    fontSize: 9,
                    color: context.palette.contrast.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: AppFonts.body(weight: FontWeight.w700).copyWith(
                fontSize: 13,
                color: context.palette.contrast,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Avatars of the people who joined the table
  Widget _buildParticipantsList() {
    if (_vm.participants.isEmpty) {
      return Text(
        'Be the first to join!',
        style: AppFonts.body().copyWith(color: context.palette.contrast.withValues(alpha: 0.4)),
      );
    }

    return Wrap(
      spacing: -12,
      children: _vm.participants.map((p) {
        return Tooltip(
          message: p.user?.name ?? 'Participant',
          child: AvatarWidget(
            url: p.user?.avatarUrl,
            name: p.user?.name,
            size: 34,
            border: Border.all(color: AppColors.accent3, width: 2),
          ),
        );
      }).toList(),
    );
  }
}
