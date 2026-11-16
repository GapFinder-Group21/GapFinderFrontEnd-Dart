import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/local_file_store.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_outbox.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/services/gap_generation_guard.dart';
import 'package:gapfinderfrontend_dart/services/gap_reminder_service.dart';
import 'package:gapfinderfrontend_dart/services/outbox_messages.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/open_table_detail_view_model.dart';

// One step of the cleanup when the session ends
class SessionCleanupStep {
  final String name;
  final Future<void> Function() action;
  const SessionCleanupStep(this.name, this.action);
}

// What the logout dialog tells the user will be removed from the phone
class LogoutWarning {
  // Actions made offline that were not sent yet (they will be lost)
  final List<String> unsent;
  // Data kept to use the app without internet
  final List<String> savedData;
  final bool isOffline;

  const LogoutWarning({required this.unsent, required this.savedData, required this.isOffline});

  bool get hasUnsent => unsent.isNotEmpty;
}

// Removes what the user that leaves did on this phone, so the next person never sees it, never gets it
// sent with their own token and never receives the reminders of the previous one.
// It is used by the logout button AND when the session expires by itself (the tokens stop working).
// Closing the app removes nothing: only logging out does.
class SessionCleanup {
  // The steps for a user. Each one has its own try: if one fails, the rest still run.
  static List<SessionCleanupStep> stepsFor(int? userId) {
    return [
      SessionCleanupStep('reminders', () => GapReminderService().cancelAll()),
      SessionCleanupStep('reminders switch', () => GapReminderService().clearEnabled()),
      SessionCleanupStep('pending actions', () => OutboxService.instance.clearAll()),
      SessionCleanupStep('queued table photos', () => LocalFileStore.instance.deleteFolder(OpenTableOutbox.photosFolder)),
      SessionCleanupStep('unpublished table photo', () => JoelLocalCache.instance.pendingPhoto.clear()),
      SessionCleanupStep('open table detail cache', () async => OpenTableDetailViewModel.clearSharedCache()),
      SessionCleanupStep('week of gaps', () => GapGenerationGuard.invalidateAll()),
      SessionCleanupStep('saved data', () => SofiaLocalCache.instance.clearUserData(userId)),
      SessionCleanupStep('onboarding step', () async {
        if (userId != null) await OnboardingPrefs().clear(userId);
      }),
    ];
  }

  // Lists what logging out removes, next to the steps above so both stay in sync.
  // Unsent actions first; silent stats (app_session, abandonments) are not listed.
  static Future<LogoutWarning> describe({
    Future<List<PendingAction>> Function()? pending,
    Future<bool> Function()? hasUnpublishedPhoto,
    bool? isOffline,
  }) async {
    final unsent = <String>[];
    try {
      final actions = await (pending ?? OutboxService.instance.pendingActions)();
      for (final a in actions) {
        final text = OutboxMessages.pending(a.type, a.label);
        if (text != null && !unsent.contains(text)) unsent.add(text);
      }
    } catch (e) {
      debugPrint('[Session] Could not read the pending actions: $e');
    }

    var photo = false;
    try {
      photo = await (hasUnpublishedPhoto ?? _hasPendingPhoto)();
    } catch (_) {}

    return LogoutWarning(
      unsent: unsent,
      savedData: [
        'Tu horario y tus huecos libres guardados',
        'Las mesas abiertas y los detalles que viste',
        'Tu recomendación guardada',
        'Los recordatorios de tus huecos',
        if (photo) 'La foto de la mesa que empezaste y no publicaste',
      ],
      isOffline: isOffline ?? !ConnectivityService.instance.isOnline,
    );
  }

  static Future<bool> _hasPendingPhoto() async =>
      await JoelLocalCache.instance.pendingPhoto.currentPath() != null;

  // Runs every step; returns the names of the steps that failed (they are also printed)
  static Future<List<String>> run(int? userId, {List<SessionCleanupStep>? steps}) async {
    final failed = <String>[];
    for (final step in steps ?? stepsFor(userId)) {
      try {
        await step.action();
      } catch (e) {
        failed.add(step.name);
        debugPrint('[Session] Could not clean ${step.name}: $e');
      }
    }
    return failed;
  }
}
