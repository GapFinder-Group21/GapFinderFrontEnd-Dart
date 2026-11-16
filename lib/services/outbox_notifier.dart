import 'dart:async';
import 'package:flutter/material.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/theme/app_colors.dart';
import 'package:gapfinderfrontend_dart/navigation/navigator_key.dart';
import 'package:gapfinderfrontend_dart/services/gap_reminder_service.dart';
import 'package:gapfinderfrontend_dart/services/outbox_messages.dart';

// Tells the user when an action made offline (join, leave, new table) was finally sent or refused.
// App open: SnackBar on the current screen. App in background: phone notification.
// Lives for the whole app; started in main.dart before the first flush.
class OutboxNotifier {
  static final OutboxNotifier instance = OutboxNotifier._();
  OutboxNotifier._();

  StreamSubscription<OutboxDelivery>? _deliverySub;
  StreamSubscription<OutboxRefusal>? _refusalSub;

  void start({OutboxService? outbox}) {
    if (_deliverySub != null) return;
    final box = outbox ?? OutboxService.instance;

    _deliverySub = box.deliveries.listen((d) {
      if (!OutboxMessages.isAnnounced(d.type)) return;
      _tell(OutboxMessages.delivered(d.type, d.label), ok: true);
    });

    _refusalSub = box.refusals.listen((r) {
      final label = r.label;
      if (label == null || !OutboxMessages.isAnnounced(r.type)) return;
      _tell(OutboxMessages.refused(r.type, label, r.message), ok: false);
    });
  }

  void _tell(String message, {required bool ok}) {
    final state = WidgetsBinding.instance.lifecycleState;
    final inForeground = state == null || state == AppLifecycleState.resumed;
    final messenger = scaffoldMessengerKey.currentState;

    if (inForeground && messenger != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(message),
        backgroundColor: ok ? AppColors.accent2 : Colors.red[700],
        duration: const Duration(seconds: 5),
      ));
      return;
    }

    // Needs the notification permission; without it only the foreground notice works
    GapReminderService()
        .showNow(ok ? 'Acción enviada' : 'Acción no enviada', message)
        .catchError((Object e) => debugPrint('Could not show the notification: $e'));
  }

  Future<void> stop() async {
    await _deliverySub?.cancel();
    await _refusalSub?.cancel();
    _deliverySub = null;
    _refusalSub = null;
  }
}
