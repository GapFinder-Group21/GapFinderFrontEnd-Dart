import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/core/utils/display_formatters.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/models/enums/day_of_week_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/services/class_block_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';

// Kind of row in the day: a class or a free gap
enum ScheduleItemType { classBlock, gap }

// One row of the day: a class or a free gap
class ScheduleItem {
  final ScheduleItemType type;
  final String name;
  final String start;
  final String end;
  final int sortMinutes;

  ScheduleItem({
    required this.type,
    required this.name,
    required this.start,
    required this.end,
    required this.sortMinutes,
  });
}

// Classes and gaps loaded from the backend
class ScheduleData {
  final List<ClassBlock> blocks;
  final List<Gap> gaps;
  ScheduleData(this.blocks, this.gaps);
}

// State and logic of the schedule tab
class ScheduleViewModel extends ChangeNotifier {
  final ClassBlockService _classBlockService;
  final GapService _gapService;
  final AuthService _authService;

  ScheduleViewModel({
    ClassBlockService? classBlockService,
    GapService? gapService,
    AuthService? authService,
  })  : _classBlockService = classBlockService ?? ClassBlockService(),
        _gapService = gapService ?? GapService(),
        _authService = authService ?? AuthService();

  ScheduleData? _data;
  bool _isLoading = true;
  String? _loadError;
  bool _disposed = false;

  ScheduleData? get data => _data;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  // True when there are no classes and no gaps at all
  bool get isEmpty => _data == null || (_data!.blocks.isEmpty && _data!.gaps.isEmpty);

  // Load the schedule when the screen opens
  Future<void> init() => refresh();

  // Generates this week's gaps and then loads the classes and the gaps
  Future<void> refresh() async {
    _isLoading = true;
    _loadError = null;
    _notify();

    try {
      _data = await _loadSchedule();
    } catch (e) {
      _loadError = '$e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

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

  // Logs out in the backend and clears the session - POST /auth/logout
  Future<void> logout() => _authService.logout();

  // Today's classes and gaps, sorted by time
  List<ScheduleItem> get todayItems {
    final data = _data;
    if (data == null) return [];

    final today = _todayEnum();
    final todayBlocks = today == null
        ? <ClassBlock>[]
        : (data.blocks.where((b) => b.dayOfWeek == today).toList()
          ..sort((a, b) => _minutesOf(a.startTime).compareTo(_minutesOf(b.startTime))));

    return _buildDayItems(todayBlocks, data.gaps);
  }

  // Minutes since midnight, used to sort the rows
  int _minutesOf(TimeOfDay time) => time.hour * 60 + time.minute;

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
        start: DisplayFormatters.timeOfDay(b.startTime),
        end: DisplayFormatters.timeOfDay(b.endTime),
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
        start: DisplayFormatters.timeOfDay(startTimeOfDay),
        end: DisplayFormatters.timeOfDay(endTimeOfDay),
        sortMinutes: _minutesOf(startTimeOfDay),
      ));
    }

    items.sort((a, b) => a.sortMinutes.compareTo(b.sortMinutes));
    return items;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
