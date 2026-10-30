import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/models/gap.dart';
import 'package:gapfinderfrontend_dart/services/app_open_delay_service.dart';
import 'package:gapfinderfrontend_dart/services/auth_service.dart';
import 'package:gapfinderfrontend_dart/services/class_block_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_generation_guard.dart';
import 'package:gapfinderfrontend_dart/services/gap_reminder_service.dart';
import 'package:gapfinderfrontend_dart/services/gap_service.dart';
import 'package:gapfinderfrontend_dart/services/session_cleanup.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';
import 'package:gapfinderfrontend_dart/viewmodels/schedule/schedule_processing.dart';

// The view and the tests keep importing ScheduleItem from here
export 'package:gapfinderfrontend_dart/viewmodels/schedule/schedule_processing.dart'
    show ScheduleItem, ScheduleItemType;

// Classes and gaps loaded from the backend
class ScheduleData {
  final List<ClassBlock> blocks;
  final List<Gap> gaps;
  ScheduleData(this.blocks, this.gaps);
}

// State and logic of the schedule tab
class ScheduleViewModel extends ChangeNotifier with OfflineAwareMixin {
  final ClassBlockService _classBlockService;
  final GapService _gapService;
  final AuthService _authService;
  final AppOpenDelayService _appOpenDelayService;
  final GapReminderService _reminderService;
  // What is removed from the phone when the user logs out (replaced in tests)
  final Future<List<String>> Function(int? userId) _sessionCleanup;

  ScheduleViewModel({
    ClassBlockService? classBlockService,
    GapService? gapService,
    AuthService? authService,
    AppOpenDelayService? appOpenDelayService,
    GapReminderService? reminderService,
    Future<List<String>> Function(int? userId)? sessionCleanup,
  })  : _sessionCleanup = sessionCleanup ?? SessionCleanup.run,
        _classBlockService = classBlockService ?? ClassBlockService(),
        _gapService = gapService ?? GapService(),
        _authService = authService ?? AuthService(),
        _appOpenDelayService = appOpenDelayService ?? AppOpenDelayService(),
        _reminderService = reminderService ?? GapReminderService();

  ScheduleData? _data;
  List<ScheduleItem> _todayItems = [];
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

  // Load the schedule when the screen opens; it reloads by itself when the connection comes back
  Future<void> init() {
    listenToConnectivity(onRestored: refresh);
    return refresh();
  }

  // Network falling back to cache: tries the network and, if it fails or there is no connection,
  // shows the schedule saved in SQLite. The spinner only shows when there is nothing on screen.
  Future<void> refresh() async {
    _isLoading = _data == null;
    _loadError = null;
    _notify();

    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) throw Exception('No hay usuario logueado');

      final loaded = await _loadFromNetworkOrCache(userId);
      _todayItems = await _buildTodayItems(loaded); // network or SQLite, both go through the isolate
      _data = loaded;
      scheduleReminders(); // not awaited: the reminders never block the schedule
    } catch (e) {
      _loadError = userMessage(e, network: 'No pudimos traer tu horario, intenta de nuevo');
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // Network first; the saved schedule when there is no connection, the call fails or it is too slow
  Future<ScheduleData> _loadFromNetworkOrCache(int userId) async {
    if (hasConnection) {
      try {
        final fresh = await _loadSchedule(userId).timeout(OfflineAwareMixin.loadTimeout);
        markFresh();
        return fresh;
      } catch (e) {
        debugPrint('Sin red para el horario, se usa lo guardado: $e');
        final saved = await _loadSaved(userId);
        // A back error with nothing saved is shown as it is
        if (saved == null) rethrow;
        return saved;
      }
    }

    final saved = await _loadSaved(userId);
    if (saved == null) throw Exception('Sin conexión y aún no tienes un horario guardado');
    return saved;
  }

  // The classes and gaps saved in SQLite, or null if there is nothing saved
  Future<ScheduleData?> _loadSaved(int userId) async {
    try {
      final cache = SofiaLocalCache.instance;
      final savedBlocks = await cache.classBlocks.getAllForUser(userId);
      final savedGaps = await cache.gaps.getAllForUser(userId);
      if (savedBlocks.isEmpty && savedGaps.isEmpty) return null;

      markFromCache(await cache.classBlocks.lastSavedAt(userId));
      return ScheduleData(savedBlocks, savedGaps);
    } catch (e) {
      debugPrint('No se pudo leer el horario guardado: $e');
      return null;
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

  Future<ScheduleData> _loadSchedule(int userId) async {
    // Recalculate the week gaps - POST /gaps/user/{userId}/generate-week. Only once per day and after the
    // class blocks change (GapGenerationGuard), not on every refresh
    if (await GapGenerationGuard.isDue(userId)) {
      try {
        await _gapService.generateWeek(userId);
        await GapGenerationGuard.markDone(userId);
      } catch (e) {
        debugPrint("Advertencia: No se pudieron sincronizar los GAPs con el servidor: $e");
      }
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
  Future<void> logout() async {
    // The user id is read first because logging out removes it
    final userId = await TokenStorage.getUserId();
    try {
      await _authService.logout();
    } finally {
      // Even if the back could not be reached, what the user did on this phone is removed
      await _sessionCleanup(userId);
    }
  }

  // Today's classes and gaps, sorted by time (calculated in an isolate when the data arrives)
  List<ScheduleItem> get todayItems => _todayItems;

  // Estrategia: Isolate. Filtering, mixing and sorting the day runs in another isolate so the
  // main one (the UI) is never blocked. The isolate only receives simple data (maps), not models.
  Future<List<ScheduleItem>> _buildTodayItems(ScheduleData data) async {
    final payload = SchedulePayload(
      classes: data.blocks
          .map((b) => <String, dynamic>{
                'subject': b.subject,
                'dayIndex': b.dayOfWeek.index,
                'startMinutes': b.startTime.hour * 60 + b.startTime.minute,
                'endMinutes': b.endTime.hour * 60 + b.endTime.minute,
              })
          .toList(),
      gaps: data.gaps
          .map((g) => <String, dynamic>{
                'startMillis': g.startTime.millisecondsSinceEpoch,
                'endMillis': g.endTime.millisecondsSinceEpoch,
              })
          .toList(),
      todayMillis: DateTime.now().millisecondsSinceEpoch,
    );
    debugPrint('ScheduleViewModel sends the work from isolate: ${Isolate.current.debugName}');
    final result = await Isolate.run(() => processSchedule(payload));
    return result.items;
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
