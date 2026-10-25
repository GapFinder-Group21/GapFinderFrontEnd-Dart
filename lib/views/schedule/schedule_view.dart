import 'package:gapfinderfrontend_dart/core/theme/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_fonts.dart';
import 'package:gapfinderfrontend_dart/navigation/app_routes.dart';
import 'package:gapfinderfrontend_dart/viewmodels/schedule/schedule_view_model.dart';
import 'package:gapfinderfrontend_dart/views/widgets/common/offline_banner.dart';

/// Schedule tab: today's classes and free gaps, in time order.
/// It also has the log out button.
class ScheduleView extends StatelessWidget {
  const ScheduleView({super.key});

  // Asks for confirmation, logs out and goes back to the welcome screen
  Future<void> _confirmLogout(BuildContext context) async {
    final vm = context.read<ScheduleViewModel>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('¿Cerrar sesión?', style: AppFonts.display(weight: FontWeight.w800)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cerrar sesión', style: TextStyle(color: AppColors.accent1)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await vm.logout();
    if (!context.mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil(AppRoutes.welcome, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<ScheduleViewModel>();

    return Scaffold(
      backgroundColor: context.palette.background,
      body: SafeArea(
        child: Column(
          children: [
            // Dark header with the app name and the log out button
            Container(
              width: double.infinity,
              color: AppColors.contrast,
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'GAP FINDER',
                      style: AppFonts.display(weight: FontWeight.w900).copyWith(
                        fontSize: 20,
                        color: Colors.white,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar sesión',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 22),
                    onPressed: () => _confirmLogout(context),
                  ),
                ],
              ),
            ),

            // Switch of the free gap reminders
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 8, 0),
              child: Row(
                children: [
                  Icon(Icons.notifications_none_rounded, size: 16, color: AppColors.contrast.withValues(alpha: 0.5)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Recordatorios de huecos libres',
                      style: AppFonts.body().copyWith(fontSize: 13, color: AppColors.contrast.withValues(alpha: 0.6)),
                    ),
                  ),
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: vm.remindersEnabled,
                      activeThumbColor: AppColors.accent2,
                      onChanged: vm.setRemindersEnabled,
                    ),
                  ),
                ],
              ),
            ),

            // Saved schedule on screen because there is no connection
            if (vm.isOffline && vm.data != null)
              OfflineBanner(
                message: 'Sin conexión · mostrando tu último horario',
                lastUpdated: vm.lastUpdated,
              ),

            // Content: loading, error, empty or the schedule
            Expanded(
              child: Builder(
                builder: (context) {
                  if (vm.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (vm.loadError != null) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          vm.isOffline
                              ? 'Sin conexión y aún no tienes un horario guardado.'
                              : vm.loadError!,
                          textAlign: TextAlign.center,
                          style: AppFonts.body().copyWith(
                            color: context.palette.contrast.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    );
                  }

                  if (vm.isEmpty) {
                    return Center(
                      child: Text(
                        'Aún no tienes clases importadas.',
                        style: AppFonts.body().copyWith(
                          color: context.palette.contrast.withValues(alpha: 0.5),
                        ),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildTodayView(context, vm.todayItems),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // "Today" view: today's classes and gaps
  Widget _buildTodayView(BuildContext context, List<ScheduleItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Text(
            'No tienes clases hoy.',
            style: AppFonts.body().copyWith(
              color: context.palette.contrast.withValues(alpha: 0.5),
            ),
          ),
        ),
      );
    }

    return Column(
      children: items.map((item) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: item.type == ScheduleItemType.classBlock
              ? _buildClassTile(context, item.name, item.start, item.end, isCompact: false)
              : _buildGapTile(context, item.start, item.end, isCompact: false),
        );
      }).toList(),
    );
  }

  // Card of a class
  Widget _buildClassTile(BuildContext context, String name, String start, String end, {required bool isCompact}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 14 : 16,
        vertical: isCompact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: context.palette.surface,
        borderRadius: BorderRadius.circular(isCompact ? 10 : 12),
        border: Border.all(
          color: context.palette.contrast.withValues(alpha: 0.10),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: isCompact ? 3 : 4,
            height: isCompact ? 28 : 36,
            decoration: BoxDecoration(
              color: AppColors.accent3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppFonts.display(weight: FontWeight.w700).copyWith(
                    fontSize: isCompact ? 13 : 14,
                    color: context.palette.contrast,
                  ),
                ),
                SizedBox(height: isCompact ? 2 : 3),
                Text(
                  '$start – $end',
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: isCompact ? 11 : 12,
                    color: context.palette.contrast.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Card of a free gap (same size as the class cards)
  Widget _buildGapTile(BuildContext context, String start, String end, {required bool isCompact}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 14 : 16,
        vertical: isCompact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: AppColors.accent1.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(isCompact ? 10 : 12),
        border: Border.all(
          color: AppColors.accent1.withValues(alpha: isCompact ? 0.38 : 0.40),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: isCompact ? 3 : 4,
            height: isCompact ? 28 : 36,
            decoration: BoxDecoration(
              color: AppColors.accent1,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'GAP',
                  style: AppFonts.display(weight: FontWeight.w800).copyWith(
                    fontSize: isCompact ? 12 : 14,
                    color: AppColors.accent1,
                    letterSpacing: 1,
                  ),
                ),
                SizedBox(height: isCompact ? 2 : 3),
                Text(
                  '$start – $end',
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: isCompact ? 11 : 12,
                    color: AppColors.accent1.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
