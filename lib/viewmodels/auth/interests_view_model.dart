import 'dart:async';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/cache/expiry_policy.dart';
import 'package:gapfinderfrontend_dart/core/cache/lru_cache.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_outbox.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';
import 'package:gapfinderfrontend_dart/viewmodels/auth/interests_processing.dart';
import 'package:gapfinderfrontend_dart/services/interest_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// State and logic of the interests onboarding step.
// The catalog is read from SQLite (the network is only asked when nothing is saved) and the
// selection is queued in the outbox when there is no connection.
class InterestsViewModel extends ChangeNotifier with OfflineAwareMixin {
  // The catalog of interests, in memory. Order: memory (LRU) -> SQLite -> network.
  // 1 entry: there is only one catalog, so a single key ("catalog") is enough.
  // 1 hour with interests: the back almost never adds an interest, so an hour old catalog is still
  // right, and it makes opening the screen again instant.
  // 30 seconds when it is empty: an empty catalog is probably an incomplete answer, so it is asked again soon.
  static final LruCache<String, List<Interest>> _cache = LruCache<String, List<Interest>>(
    maxEntries: 1,
    name: 'interests catalog',
    expiryPolicy: ValueBasedExpiry<String, List<Interest>>(catalogExpiry),
  );
  static const _catalogKey = 'catalog';

  // How long the catalog is kept in memory: less when it has no interests
  @visibleForTesting
  static Duration? catalogExpiry(String key, List<Interest> interests) =>
      interests.isEmpty ? const Duration(seconds: 30) : const Duration(hours: 1);

  // Empties the memory cache (for tests)
  @visibleForTesting
  static void clearCache() => _cache.clear();

  static const offlineNotice = 'Tus intereses se guardarán cuando vuelva la conexión';

  final InterestService _interestService;
  final UserService _userService;
  final MiguelLocalCache _localCache;
  final OutboxService? _outbox;

  InterestsViewModel({
    InterestService? interestService,
    UserService? userService,
    MiguelLocalCache? localCache,
    this._outbox,
  })  : _interestService = interestService ?? InterestService(),
        _userService = userService ?? UserService(),
        _localCache = localCache ?? MiguelLocalCache.instance;

  OutboxService get _outboxService => _outbox ?? OutboxService.instance;

  List<Interest> _interests = [];
  final Map<int, String> _searchNames = {};
  final Set<int> _selectedInterestIds = {};
  bool _isLoading = true;
  String? _loadError;
  bool _isSaving = false;
  String? _errorMessage;
  String? _notice;
  bool _disposed = false;
  int? _userId;
  Set<int>? _queuedSelection;
  Set<String> _pendingKeys = {};
  StreamSubscription<Set<String>>? _pendingSub;

  List<Interest> get interests => _interests;

  // The name in lower case and without accents, made by the isolate (to search)
  String searchNameOf(Interest interest) => _searchNames[interest.id] ?? normalizeInterestName(interest.name);
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  bool isSelected(int id) => _selectedInterestIds.contains(id);

  // The selection is waiting in the outbox and has not changed since: the button says "Pendiente de enviar"
  bool get isSavePending {
    final queued = _queuedSelection;
    final userId = _userId;
    if (queued == null || userId == null || !_pendingKeys.contains(UserInterestsOutbox.key(userId))) return false;
    return setEquals(queued, _selectedInterestIds);
  }

  // Message for the View after save() when nothing failed but nothing was sent yet. It is read once.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  // Loads the catalog when the screen opens. It loads again by itself when the connection comes
  // back (only if there was no catalog) and when the outbox sends the pending selection.
  // Estrategia: Future con handler + async/await. The await waits for the catalog; the handlers
  // (.then / .catchError) say what happens when it ends well or when it fails, without a try/catch.
  Future<void> init() async {
    _localCache.advanceOnboarding(OnboardingStep.interests);
    listenToConnectivity(onRestored: () async {
      if (_interests.isEmpty) await _loadCatalog();
    });
    _watchOutbox();

    await _loadCatalog().then((_) {
      debugPrint('[Intereses] catálogo listo: ${_interests.length}');
    }).catchError((Object e) {
      _loadError = '$e';
      _isLoading = false;
      _notify();
    });
  }

  // Estrategia: Stream. The outbox sends a new set of pending keys every time the queue changes;
  // the subscription is cancelled in dispose.
  void _watchOutbox() {
    try {
      _pendingSub = _outboxService.pendingKeys.listen((keys) {
        final userId = _userId;
        final key = userId == null ? null : UserInterestsOutbox.key(userId);
        final sent = key != null && _pendingKeys.contains(key) && !keys.contains(key);
        _pendingKeys = keys;
        _notify();
        if (sent) _onSent();
      }, onError: (e) => debugPrint('Error watching the outbox: $e'));
    } catch (e) {
      debugPrint('Could not watch the outbox: $e');
    }
  }

  // The pending selection reached the back: the button goes back to normal
  void _onSent() {
    _queuedSelection = null;
    _notify();
  }

  void _logCache(String result) => debugPrint('$result ${_cache.describe()}');

  // Memory (LRU) -> SQLite -> network: a fresh LRU entry is enough; on a miss the saved catalog is
  // used, and the network is only asked if nothing is saved
  Future<void> _loadCatalog() async {
    _isLoading = _interests.isEmpty;
    _loadError = null;
    _notify();

    try {
      _userId ??= await TokenStorage.getUserId();

      final cached = _cache.get(_catalogKey);
      if (cached != null) {
        _logCache('HIT');
        _interests = cached;
        await _loadSelection();
        return;
      }
      _logCache('MISS');

      final saved = await _localCache.interestsCatalog.getAll();
      if (saved.isNotEmpty) {
        _interests = await _process(saved);
        _cache.put(_catalogKey, _interests);
        markUpdatedAt(await _localCache.interestsCatalog.lastSavedAt());
      } else if (hasConnection) {
        final loaded = await _interestService.getInterests().timeout(OfflineAwareMixin.loadTimeout);
        _interests = await _process(loaded);
        _cache.put(_catalogKey, _interests);
        _localCache.saveInterestsCatalog(_interests);
        markFresh();
      } else {
        _loadError = 'Sin conexión y aún no tenemos el catálogo de intereses; se cargará cuando vuelva la conexión';
      }

      await _loadSelection();
    } catch (e) {
      _loadError = isNetworkError(e)
          ? 'No pudimos cargar los intereses; se cargarán cuando vuelva la conexión'
          : '$e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // Estrategia: Isolate. Normalizing the names, removing the duplicates and sorting runs in another
  // isolate so a long catalog never blocks the screen. processInterests is a top-level function and
  // gets only simple data (maps), because an isolate does not share memory with the app.
  Future<List<Interest>> _process(List<Interest> interests) async {
    final raw = interests.map((i) => i.toJson()).toList();
    debugPrint('InterestsViewModel sends the work from isolate: ${Isolate.current.debugName}');
    final processed = await Isolate.run(() => processInterests(raw));

    _searchNames.clear();
    for (final item in processed) {
      _searchNames[item['id'] as int] = item['searchName'] as String;
    }
    return processed.map((item) => Interest(id: item['id'] as int, name: item['name'] as String)).toList();
  }

  // Estrategia: Future. It returns when the saved interests of this user are read from SQLite.
  Future<void> _loadSelection() async {
    final userId = _userId;
    if (userId == null || _selectedInterestIds.isNotEmpty) return;

    try {
      final rows = await _localCache.userInterests.getAllForUser(userId);
      _selectedInterestIds.addAll(rows.map((r) => r.interestId));
    } catch (e) {
      debugPrint('Could not read the saved interests: $e');
    }
  }

  // Select or unselect an interest
  void toggleInterest(int id) {
    if (_selectedInterestIds.contains(id)) {
      _selectedInterestIds.remove(id);
    } else {
      _selectedInterestIds.add(id);
    }
    _notify();
  }

  // Saves the selected interests; returns true when they were sent or queued to be sent
  // - POST /users/{userId}/interests/{interestId} for each one.
  // Without connection (or if the network fails) the selection is saved in SQLite with synced = 0
  // and queued with the key user_interests_save:<userId>; the last selection replaces the pending one.
  Future<bool> save() async {
    _errorMessage = null;

    if (_selectedInterestIds.isEmpty) {
      _errorMessage = 'Please select at least one interest';
      return false;
    }

    _isSaving = true;
    _notify();

    // The interests the back already received (saved with synced = 1)
    final sent = <int>{};
    final chosen = Set<int>.of(_selectedInterestIds);
    int? savedUserId;

    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) throw Exception('User session not found');
      savedUserId = userId;
      _userId = userId;

      // Only the difference is sent: the new interests with POST and the unticked ones with DELETE
      final diff = await _selectionDiff(userId, chosen);
      sent.addAll(diff.alreadySynced);

      if (!hasConnection) return await _queue(userId, chosen, diff);

      try {
        // POST /users/{userId}/interests/{interestId}, DELETE /users/{userId}/interests/{interestId}
        for (final interestId in diff.add) {
          await _userService.addInterest(userId, interestId).timeout(OfflineAwareMixin.loadTimeout);
          sent.add(interestId);
        }
        for (final interestId in diff.remove) {
          await _userService.removeInterest(userId, interestId).timeout(OfflineAwareMixin.loadTimeout);
        }
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        return await _queue(userId, chosen, diff);
      }

      // It worked: a selection that was still pending is not needed anymore
      await _outboxService.cancelPending(UserInterestsOutbox.key(userId));
      _queuedSelection = null;
      _localCache.advanceOnboarding(OnboardingStep.scheduleSetup);
      return true;
    } catch (e) {
      _errorMessage = 'Error saving interests: $e';
      return false;
    } finally {
      // The chosen interests are kept in SQLite, with synced = 1 only for the ones that were sent
      if (savedUserId != null) {
        _localCache.saveUserInterests(savedUserId, chosen, sent);
      }
      _isSaving = false;
      _notify();
    }
  }

  // Compares the new selection with what SQLite had before this save:
  // add = chosen and not yet received by the back; remove = had before and now unticked, plus the
  // unticked ones that a pending selection still had to delete (its row is replaced, not sent)
  Future<_SelectionDiff> _selectionDiff(int userId, Set<int> chosen) async {
    var before = <UserInterestRow>[];
    try {
      before = await _localCache.userInterests.getAllForUser(userId);
    } catch (e) {
      debugPrint('Could not read the saved interests: $e');
    }
    final pendingRemove = await UserInterestsOutbox.pendingRemoveIds(userId, outbox: _outboxService);

    final synced = before.where((r) => r.synced).map((r) => r.interestId).toSet();
    return _SelectionDiff(
      add: chosen.difference(synced),
      remove: before.map((r) => r.interestId).toSet().union(pendingRemove).difference(chosen),
      alreadySynced: chosen.intersection(synced),
    );
  }

  // The dedupeKey lets only one selection wait in the outbox, so many taps send it once
  Future<bool> _queue(int userId, Set<int> chosen, _SelectionDiff diff) async {
    await UserInterestsOutbox.enqueue(userId, chosen, addIds: diff.add, removeIds: diff.remove, outbox: _outbox);
    _queuedSelection = chosen;
    _pendingKeys = {..._pendingKeys, UserInterestsOutbox.key(userId)};
    _notice = offlineNotice;
    _localCache.advanceOnboarding(OnboardingStep.scheduleSetup);
    return true;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingSub?.cancel();
    super.dispose();
  }
}

// What a save has to send to the back
class _SelectionDiff {
  final Set<int> add;
  final Set<int> remove;
  final Set<int> alreadySynced;

  const _SelectionDiff({required this.add, required this.remove, required this.alreadySynced});
}
