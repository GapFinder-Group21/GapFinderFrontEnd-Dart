import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/google_import_store.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/interests_catalog_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/register_draft_store.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/seen_candidates_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_dao.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';

// What the view models of the onboarding and the match call to save on the device.
// Every method returns at once (fire and forget): saving never blocks or breaks a screen,
// and if it fails it only prints.
class MiguelLocalCache {
  static final MiguelLocalCache instance = MiguelLocalCache();

  final InterestsCatalogDao interestsCatalog;
  final UserInterestsDao userInterests;
  final SeenCandidatesDao seenCandidates;
  final RegisterDraftStore registerDraft;
  final GoogleImportStore googleImport;
  final OnboardingPrefs onboarding;

  MiguelLocalCache({
    InterestsCatalogDao? interestsCatalog,
    UserInterestsDao? userInterests,
    SeenCandidatesDao? seenCandidates,
    RegisterDraftStore? registerDraft,
    GoogleImportStore? googleImport,
    OnboardingPrefs? onboarding,
  })  : interestsCatalog = interestsCatalog ?? InterestsCatalogDao(),
        userInterests = userInterests ?? UserInterestsDao(),
        seenCandidates = seenCandidates ?? SeenCandidatesDao(),
        registerDraft = registerDraft ?? RegisterDraftStore(),
        googleImport = googleImport ?? GoogleImportStore(),
        onboarding = onboarding ?? OnboardingPrefs();

  // SQLite: the catalog the back answered
  void saveInterestsCatalog(List<Interest> interests) {
    _run('interests catalog', () => interestsCatalog.replaceAll(interests));
  }

  // SQLite: the interests the user chose; syncedIds are the ones the back already received.
  // It never throws; the caller can wait for it (the interests are written before they are queued).
  Future<void> saveUserInterests(int userId, Set<int> interestIds, Set<int> syncedIds) {
    return _run('user interests', () => userInterests.replaceAllForUser(userId, interestIds, syncedIds));
  }

  // SQLite: the candidate that was shown for a match
  void saveSeenCandidate(int matchId, MatchCandidate candidate) {
    _run('seen candidate', () => seenCandidates.save(matchId, candidate));
  }

  // SQLite: the candidate of a request that waits in the outbox (it has no match id yet)
  void saveQueuedCandidate(int proposerGapId, MatchCandidate candidate) {
    _run('queued candidate', () => seenCandidates.saveQueued(proposerGapId, candidate.acceptorGap.id, candidate));
  }

  // SQLite: forgets the candidate of a queued request that was confirmed or cancelled
  void forgetQueuedCandidate(int proposerGapId, MatchCandidate candidate) {
    _run('queued candidate cleanup', () => seenCandidates.deleteQueued(proposerGapId, candidate.acceptorGap.id));
  }

  // Hive: what the user has typed so far in the sign up form
  void saveRegisterDraft(RegisterDraft draft) {
    _run('register draft', () => registerDraft.save(draft));
  }

  void clearRegisterDraft() {
    _run('register draft cleanup', registerDraft.clear);
  }

  // File: how the last Google Calendar import ended
  void saveGoogleImport({required bool success, required String message}) {
    _run('google import', () => googleImport.save(GoogleImportState(date: DateTime.now(), success: success, message: message)));
  }

  // SharedPreferences: the step of the onboarding where the user of the session is.
  // Without a session there is no user to save it for, so nothing is saved.
  void advanceOnboarding(OnboardingStep step) {
    _run('onboarding step', () async {
      final userId = await TokenStorage.getUserId();
      if (userId != null) await onboarding.advanceTo(userId, step);
    });
  }

  // A new account was created: its onboarding starts again at the interests
  void startOnboarding() {
    _run('onboarding start', () async {
      final userId = await TokenStorage.getUserId();
      if (userId != null) await onboarding.start(userId);
    });
  }

  Future<void> _run(String what, Future<void> Function() action) {
    return Future.sync(action).catchError((Object e) {
      debugPrint('Could not save $what locally: $e');
    });
  }
}
