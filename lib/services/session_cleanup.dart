import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/services/gap_generation_guard.dart';
import 'package:gapfinderfrontend_dart/services/gap_reminder_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/open_tables/open_table_detail_view_model.dart';

// One step of the cleanup when the session ends
class SessionCleanupStep {
  final String name;
  final Future<void> Function() action;
  const SessionCleanupStep(this.name, this.action);
}

// Removes what the user that leaves did on this phone, so the next person never sees it, never gets it
// sent with their own token and never receives the reminders of the previous one.
// It is used by the logout button AND when the session expires by itself (the tokens stop working).
class SessionCleanup {
  // The steps for a user. Each one has its own try: if one fails, the rest still run.
  static List<SessionCleanupStep> stepsFor(int? userId) {
    return [
      SessionCleanupStep('reminders', () => GapReminderService().cancelAll()),
      SessionCleanupStep('reminders switch', () => GapReminderService().clearEnabled()),
      SessionCleanupStep('pending actions', () => OutboxService.instance.clearAll()),
      SessionCleanupStep('open table detail cache', () async => OpenTableDetailViewModel.clearSharedCache()),
      SessionCleanupStep('week of gaps', () => GapGenerationGuard.invalidateAll()),
      SessionCleanupStep('saved data', () => SofiaLocalCache.instance.clearUserData(userId)),
      SessionCleanupStep('onboarding step', () async {
        if (userId != null) await OnboardingPrefs().clear(userId);
      }),
    ];
  }

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
