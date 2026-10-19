import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/core/utils/display_formatters.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/models/enums/day_of_week_enum.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/services/app_open_delay_service.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/services/class_block_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_reminder_service.dart';
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
  final AppOpenDelayService _appOpenDelayService;
  final GapReminderService _reminderService;

  ScheduleViewModel({
    ClassBlockService? classBlockService,
    GapService? gapService,
    AuthService? authService,
    AppOpenDelayService? appOpenDelayService,
    GapReminderService? reminderService,
  })  : _classBlockService = classBlockService ?? ClassBlockService(),
        _gapService = gapService ?? GapService(),
        _authService = authService ?? AuthService(),
        _appOpenDelayService = appOpenDelayService ?? AppOpenDelayService(),
        _reminderService = reminderService ?? GapReminderService();

  ScheduleData? _data;
  bool _isLoading = true;
  String? _loadError;
  bool _remindersEnabled = false;
  Future<void>? _reminderSetting;
  bool _disposed = false;

  ScheduleData? get data => _data;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  bool get remindersEnabled => _remindersEnabled;

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
      scheduleReminders(); // not awaited: the reminders never block the schedule
    } catch (e) {
      _loadError = '$e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // Reads the saved switch; the first time it asks the notification permission and turns on if granted
  Future<void> _loadReminderSetting() {
    return _reminderSetting ??= () async {
      final saved = await _reminderService.loadEnabled();
      if (saved != null) {
        _remindersEnabled = saved;
      } else {
        _remindersEnabled = await _reminderService.requestPermission();
        await _reminderService.saveEnabled(_remindersEnabled);
      }
      _notify();
    }();
  }

  // Schedules a reminder for each gap of today, at the time the BQ says the student usually opens the app.
  // Also called when the app comes back to the foreground. If anything fails it only prints.
  Future<void> scheduleReminders() async {
    try {
      await _loadReminderSetting();
      final data = _data;
      if (!_remindersEnabled || data == null) return;

      final userId = await TokenStorage.getUserId();
      if (userId == null) return;

      // GET /analytics/app-open-delay/user/{userId} (5 minutes if it fails)
      final offset = await _appOpenDelayService.getOffsetMinutes(userId);
      await _reminderService.scheduleForGaps(data.gaps, offset);
    } catch (e) {
      debugPrint('No se pudieron programar los recordatorios: $e');
    }
  }

  // The switch of the schedule: turns the reminders on (asking the permission) or off
  Future<void> setRemindersEnabled(bool enabled) async {
    try {
      if (enabled && !await _reminderService.requestPermission()) {
        enabled = false; // the permission was denied
      }

      _remindersEnabled = enabled;
      _reminderSetting = Future.value();
      _notify();
      await _reminderService.saveEnabled(enabled);

      if (enabled) {
        await scheduleReminders();
      } else {
        await _reminderService.cancelAll();
      }
    } catch (e) {
      debugPrint('No se pudo cambiar el recordatorio: $e');
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

    final blocks = results[0] as List<ClassBlock>;
    final gaps = results[1] as List<Gap>;

    // Save what the network answered; it is not awaited and never breaks the screen
    SofiaLocalCache.instance.saveSchedule(userId, blocks, gaps);

    return ScheduleData(blocks, gaps);
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
