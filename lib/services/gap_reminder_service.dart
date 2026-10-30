import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;
import 'package:gapfinderfrontend_dart/models/gap.dart';

// A reminder ready to be scheduled
class GapReminder {
  final int gapId;
  final DateTime fireAt;
  final int minutesLeft;
  // The id of the notification: it comes from the start of the gap, not from the id of the gap, because the
  // gap ids can change when the back recalculates the week, and then the old reminders could not be cancelled
  final int notificationId;
  GapReminder(this.gapId, this.fireAt, this.minutesLeft, this.notificationId);
}

// Local notifications that remind the student of the free gaps of today
class GapReminderService {
  static final GapReminderService _instance = GapReminderService._();
  factory GapReminderService() => _instance;
  GapReminderService._();

  // A reminder only makes sense if the gap still has this many minutes when it arrives
  static const minMinutesLeft = 15;

  static const _channelId = 'gap_reminders';
  static const _openTablesPayload = 'open_tables';
  static const _enabledKey = 'gap_reminders_enabled';
  // The ids of the notifications this service scheduled: only these are cancelled, never other notifications
  static const _scheduledIdsKey = 'gap_reminder_ids';

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<void>.broadcast();
  bool _initialized = false;
  bool _openTablesRequested = false;

  // Fires when the user taps a reminder while the app is running
  Stream<void> get taps => _taps.stream;

  // True if the app was opened from a reminder and nobody has handled it yet
  bool takeOpenTablesRequest() {
    final requested = _openTablesRequested;
    _openTablesRequested = false;
    return requested;
  }

  // Sets the time zone and the plugin; safe to call many times
  Future<void> init() async {
    if (_initialized) return;

    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('America/Bogota'));

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // The permission is asked later, from the switch in the schedule
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    // The app was closed and the user opened it by tapping a reminder
    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true &&
        launch?.notificationResponse?.payload == _openTablesPayload) {
      _openTablesRequested = true;
    }

    _initialized = true;
  }

  void _onTap(NotificationResponse response) {
    if (response.payload != _openTablesPayload) return;
    _openTablesRequested = true;
    _taps.add(null);
  }

  // Asks the notification permission (Android 13+ and iOS); returns true if it was granted
  Future<bool> requestPermission() async {
    await init();

    final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, badge: true, sound: true) ?? false;
    }

    return false;
  }

  // The switch of the schedule: null means the user has never chosen
  Future<bool?> loadEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_enabledKey);
  }

  Future<void> saveEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
  }

  // Forgets the switch (logout): the next user is asked again the first time, they do not inherit it
  Future<void> clearEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_enabledKey);
  }

  // A stable id from the start of the gap (minutes since 1970, 30 bits so it is a valid notification id)
  static int notificationIdFor(DateTime gapStart) => (gapStart.millisecondsSinceEpoch ~/ 60000) & 0x3fffffff;

  // Which reminders to schedule: one per gap of today, offsetMinutes after it starts,
  // only if that moment has not passed and the gap still has minMinutesLeft minutes then
  static List<GapReminder> plan(List<Gap> gaps, int offsetMinutes, DateTime now) {
    final reminders = <GapReminder>[];

    for (final gap in gaps) {
      final isToday = gap.startTime.year == now.year &&
          gap.startTime.month == now.month &&
          gap.startTime.day == now.day;
      if (!isToday) continue;

      final fireAt = gap.startTime.add(Duration(minutes: offsetMinutes));
      if (!fireAt.isAfter(now)) continue;

      final minutesLeft = gap.endTime.difference(fireAt).inMinutes;
      if (minutesLeft < minMinutesLeft) continue;

      reminders.add(GapReminder(gap.id, fireAt, minutesLeft, notificationIdFor(gap.startTime)));
    }

    return reminders;
  }

  // Cancels the old reminders (only the ones scheduled by this service) and schedules the ones of today
  Future<void> scheduleForGaps(List<Gap> gaps, int offsetMinutes) async {
    await init();
    await _cancelScheduledReminders();

    final scheduledIds = <int>[];
    for (final reminder in plan(gaps, offsetMinutes, DateTime.now())) {
      scheduledIds.add(reminder.notificationId);
      await _plugin.zonedSchedule(
        id: reminder.notificationId,
        title: 'Tienes tiempo libre',
        body: 'Tienes ${reminder.minutesLeft} min libres hasta tu próxima clase. '
            'Hay Open Tables cerca de ti',
        scheduledDate: tz.TZDateTime.from(reminder.fireAt, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Recordatorios de huecos libres',
            channelDescription: 'Avisos cuando empieza un hueco libre en tu horario',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        // Inexact: no special permission for exact alarms is needed
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: _openTablesPayload,
      );
    }

    await _saveScheduledIds(scheduledIds);
  }

  // Cancels every reminder of this service (for example when the user logs out). Other notifications stay.
  Future<void> cancelAll() async {
    await init();
    await _cancelScheduledReminders();
  }

  Future<void> _cancelScheduledReminders() async {
    final prefs = await SharedPreferences.getInstance();
    final ids = prefs.getStringList(_scheduledIdsKey) ?? const <String>[];
    for (final id in ids) {
      final parsed = int.tryParse(id);
      if (parsed != null) await _plugin.cancel(id: parsed);
    }
    await prefs.remove(_scheduledIdsKey);
  }

  Future<void> _saveScheduledIds(List<int> ids) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_scheduledIdsKey, ids.map((id) => id.toString()).toList());
  }
}
