import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/cache/lru_cache.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_outbox.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';
import 'package:gapfinderfrontend_dart/services/interest_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// State and logic of the interests onboarding step.
// The catalog is read from SQLite (the network is only asked when nothing is saved) and the
// selection is queued in the outbox when there is no connection.
class InterestsViewModel extends ChangeNotifier with OfflineAwareMixin {
  // The catalog of interests, in memory. Order: memory (LRU) -> SQLite -> network.
  // 1 entry: there is only one catalog, so a single key ("catalog") is enough.
  // 1 hour: the back almost never adds an interest, so an hour old catalog is still right, and it
  // makes opening the screen again instant. After an hour it is read again from SQLite / the network.
  static final LruCache<String, List<Interest>> _cache =
      LruCache<String, List<Interest>>(maxEntries: 1, ttl: const Duration(hours: 1));
  static const _catalogKey = 'catalog';

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
  Future<void> init() {
    _localCache.advanceOnboarding(OnboardingStep.interests);
    listenToConnectivity(onRestored: () async {
      if (_interests.isEmpty) await _loadCatalog();
    });
    _watchOutbox();
    return _loadCatalog();
  }

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

  void _logCache(String result) =>
      debugPrint('[LRU intereses] $result (hits=${_cache.hits}, misses=${_cache.misses}, size=${_cache.length})');

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
        _logCache('ACIERTO');
        _interests = cached;
        await _loadSelection();
        return;
      }
      _logCache('FALLO');

      final saved = await _localCache.interestsCatalog.getAll();
      if (saved.isNotEmpty) {
        _interests = saved;
        _cache.put(_catalogKey, saved);
        markUpdatedAt(await _localCache.interestsCatalog.lastSavedAt());
      } else if (hasConnection) {
        _interests = await _interestService.getInterests().timeout(OfflineAwareMixin.loadTimeout);
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

  // The interests this user already chose, saved in SQLite
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

      if (!hasConnection) return await _queue(userId, chosen);

      try {
        // Save each selected interest one by one - POST /users/{userId}/interests/{interestId}
        for (final interestId in chosen) {
          await _userService.addInterest(userId, interestId).timeout(OfflineAwareMixin.loadTimeout);
          sent.add(interestId);
        }
      } catch (e) {
        if (!isNetworkError(e)) rethrow;
        return await _queue(userId, chosen);
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

  // The dedupeKey lets only one selection wait in the outbox, so many taps send it once
  Future<bool> _queue(int userId, Set<int> chosen) async {
    await UserInterestsOutbox.enqueue(userId, chosen, outbox: _outbox);
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
