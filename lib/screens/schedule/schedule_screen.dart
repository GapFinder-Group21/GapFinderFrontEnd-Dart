import 'package:flutter/material.dart';
import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../core/token_storage.dart';
import '../../models/class_block.dart';
import '../../models/day_of_week_enum.dart';
import '../../models/gap.dart';
import '../../services/auth_service.dart';
import '../../services/class_block_service.dart';
import '../../services/gap_service.dart';

// Helper types used only by this screen
enum ScheduleItemType { classBlock, gap }

// One row of the day: a class or a free gap
class ScheduleItem {
  final ScheduleItemType type;
  final String name;
  final String start;
  final String end;
  final int? gapId;
  final int sortMinutes;

  ScheduleItem({
    required this.type,
    required this.name,
    required this.start,
    required this.end,
    this.gapId,
    required this.sortMinutes,
  });
}

// Classes and gaps loaded from the backend
class ScheduleData {
  final List<ClassBlock> blocks;
  final List<Gap> gaps;
  ScheduleData(this.blocks, this.gaps);
}

/// Schedule tab: today's classes and free gaps, in time order.
/// It also has the log out button.
class ScheduleScreen extends StatefulWidget {
  final bool isActive;
  const ScheduleScreen({super.key, this.isActive = false});

  @override
  State<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends State<ScheduleScreen> {
  final _classBlockService = ClassBlockService();
  final _gapService = GapService();
  late Future<ScheduleData> _scheduleFuture;

  @override
  // Load the schedule when the screen opens
  void initState() {
    super.initState();
    _scheduleFuture = _loadSchedule();
  }

  @override
  // Reload the schedule every time the user comes back to this tab
  void didUpdateWidget(covariant ScheduleScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      setState(() {
        _scheduleFuture = _loadSchedule();
      });
    }
  }

  // Generates this week's gaps and then loads the classes and the gaps
  Future<ScheduleData> _loadSchedule() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) {
      throw Exception('No hay usuario logueado');
    }

    // Recalculate the week gaps - POST /gaps/user/{userId}/generate-week
    try {
      await _gapService.generateWeek(userId);
    } catch (e) {
      debugPrint("Advertencia: No se pudieron sincronizar los GAPs con el servidor: $e");
    }

    final results = await Future.wait([
      _classBlockService.getByUser(userId),
      _gapService.getUserGaps(userId),
    ]);

    return ScheduleData(
      results[0] as List<ClassBlock>,
      results[1] as List<Gap>,
    );
  }

  // Asks for confirmation, logs out and goes back to the welcome screen - POST /auth/logout
  Future<void> _confirmLogout() async {
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

    await AuthService().logout();
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/welcome', (route) => false);
  }

  // Minutes since midnight, used to sort the rows
  int _minutesOf(TimeOfDay time) => time.hour * 60 + time.minute;

  // TimeOfDay -> "8:00" / "2:30" (12h format without AM/PM)
  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // Today as a day enum (MON ... SUN)
  DayOfWeekEnum? _todayEnum() {
    final index = DateTime.now().weekday - 1;
    return index < DayOfWeekEnum.values.length ? DayOfWeekEnum.values[index] : null;
  }

  // Builds today's list of classes and gaps, sorted by time
  List<ScheduleItem> _buildDayItems(List<ClassBlock> blocks, List<Gap> gaps) {
    final items = <ScheduleItem>[];

    for (final b in blocks) {
      items.add(ScheduleItem(
        type: ScheduleItemType.classBlock,
        name: b.subject,
        start: _formatTime(b.startTime),
        end: _formatTime(b.endTime),
        sortMinutes: _minutesOf(b.startTime),
      ));
    }

    final now = DateTime.now();
    final todayGaps = gaps.where((g) =>
        g.startTime.year == now.year &&
        g.startTime.month == now.month &&
        g.startTime.day == now.day
    ).toList();

    for (final g in todayGaps) {
      final startTimeOfDay = TimeOfDay.fromDateTime(g.startTime);
      final endTimeOfDay = TimeOfDay.fromDateTime(g.endTime);
      items.add(ScheduleItem(
        type: ScheduleItemType.gap,
        name: 'GAP',
        start: _formatTime(startTimeOfDay),
        end: _formatTime(endTimeOfDay),
        gapId: g.id,
        sortMinutes: _minutesOf(startTimeOfDay),
      ));
    }

    items.sort((a, b) => a.sortMinutes.compareTo(b.sortMinutes));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
                    onPressed: _confirmLogout,
                  ),
                ],
              ),
            ),

            // Content: loading, error, empty or the schedule
            Expanded(
              child: FutureBuilder<ScheduleData>(
                future: _scheduleFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No se pudo cargar tu horario.\n${snapshot.error}',
                          textAlign: TextAlign.center,
                          style: AppFonts.body().copyWith(
                            color: AppColors.contrast.withValues(alpha: 0.6),
                          ),
                        ),
                      ),
                    );
                  }

                  final data = snapshot.data;
                  if (data == null || (data.blocks.isEmpty && data.gaps.isEmpty)) {
                    return Center(
                      child: Text(
                        'Aún no tienes clases importadas.',
                        style: AppFonts.body().copyWith(
                          color: AppColors.contrast.withValues(alpha: 0.5),
                        ),
                      ),
                    );
                  }

                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: _buildTodayView(data.blocks, data.gaps),
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
  Widget _buildTodayView(List<ClassBlock> blocks, List<Gap> gaps) {
    final today = _todayEnum();
    final todayBlocks = today == null
        ? <ClassBlock>[]
        : (blocks.where((b) => b.dayOfWeek == today).toList()
          ..sort((a, b) => _minutesOf(a.startTime).compareTo(_minutesOf(b.startTime))));

    final items = _buildDayItems(todayBlocks, gaps);

    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 40),
          child: Text(
            'No tienes clases hoy.',
            style: AppFonts.body().copyWith(
              color: AppColors.contrast.withValues(alpha: 0.5),
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
              ? _buildClassTile(item.name, item.start, item.end, isCompact: false)
              : _buildGapTile(item.start, item.end, isCompact: false),
        );
      }).toList(),
    );
  }

  // Card of a class
  Widget _buildClassTile(String name, String start, String end, {required bool isCompact}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 14 : 16,
        vertical: isCompact ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(isCompact ? 10 : 12),
        border: Border.all(
          color: AppColors.contrast.withValues(alpha: 0.10),
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
                    color: AppColors.contrast,
                  ),
                ),
                SizedBox(height: isCompact ? 2 : 3),
                Text(
                  '$start – $end',
                  style: AppFonts.body(weight: FontWeight.w400).copyWith(
                    fontSize: isCompact ? 11 : 12,
                    color: AppColors.contrast.withValues(alpha: 0.5),
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
  Widget _buildGapTile(String start, String end, {required bool isCompact}) {
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
