import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/cache/expiry_policy.dart';
import 'package:gapfinderfrontend_dart/core/cache/lru_cache.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/match_history_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/match_rating_outbox.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/rating_drafts_hive_store.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/match_history_item.dart';
import 'package:gapfinderfrontend_dart/services/match_rating_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/match/match_history_processing.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// The chips of the screen
enum MatchHistoryFilter { toRate, rated, all }

// Runs processMatchHistory somewhere (another isolate in the app; called directly in tests)
typedef MatchHistoryProcessor = Future<MatchHistoryResult> Function(MatchHistoryPayload payload);

// State and logic of "Mis matches": the history of the user's matches and their ratings
class MyMatchesViewModel extends ChangeNotifier with OfflineAwareMixin {
  // Estrategia: Caching (LRU, memory → SQLite → network). One entry per user (key = user id) with the
  // history as the back sent it. ValueBasedExpiry: 1 minute if there is an ACCEPTED match (it will
  // become COMPLETED soon and then it can be rated), 10 minutes if not (old matches do not change).
  static final LruCache<int, List<MatchHistoryItem>> _cache = LruCache<int, List<MatchHistoryItem>>(
    maxEntries: 4,
    name: 'mis matches',
    expiryPolicy: ValueBasedExpiry<int, List<MatchHistoryItem>>((_, items) => historyExpiry(items)),
  );

  static const _shortLife = Duration(minutes: 1);
  static const _longLife = Duration(minutes: 10);

  // How long a history in memory is trusted
  @visibleForTesting
  static Duration historyExpiry(List<MatchHistoryItem> items) =>
      items.any((i) => i.status == MatchStatusEnum.ACCEPTED) ? _shortLife : _longLife;

  // Empties the history in memory (logout and tests)
  static void clearHistoryCache() => _cache.clear();

  static const maxComment = 300;
  static const queuedNotice = 'Sin conexión: tu calificación se enviará cuando vuelva el internet';
  static const sentNotice = 'Tu calificación se envió';
  static const alreadyRated = 'Ya calificaste este match';

  final MatchRatingService _service;
  final MatchHistoryDao _dao;
  final RatingDraftsHiveStore _drafts;
  final OutboxService _outbox;
  final ConnectivityService _connectivity;
  final Future<int?> Function() _readUserId;
  final MatchHistoryProcessor _process;

  MyMatchesViewModel({
    MatchRatingService? service,
    MatchHistoryDao? dao,
    RatingDraftsHiveStore? drafts,
    OutboxService? outbox,
    ConnectivityService? connectivity,
    Future<int?> Function()? readUserId,
    MatchHistoryProcessor? process,
  })  : _service = service ?? MatchRatingService(),
        _dao = dao ?? MatchHistoryDao(),
        _drafts = drafts ?? RatingDraftsHiveStore(),
        _outbox = outbox ?? OutboxService.instance,
        _connectivity = connectivity ?? ConnectivityService.instance,
        _readUserId = readUserId ?? TokenStorage.getUserId,
        _process = process ?? processMatchHistoryInIsolate;

  int? _userId;
  // The history as the back sent it (without the pending ratings)
  List<MatchHistoryItem> _base = [];
  MatchHistoryResult _result = MatchHistoryResult.empty;
  MatchHistoryFilter _filter = MatchHistoryFilter.toRate;
  bool _hasLoaded = false;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  String? _notice;
  bool _disposed = false;
  int _loadSeq = 0;
  StreamSubscription<Set<String>>? _pendingSub;
  // Keys of my ratings that wait in the outbox
  Set<String> _pendingKeys = {};
  // The ratings that wait in the outbox, by match id (shown at once, optimistic)
  Map<int, MatchRating> _pendingRatings = {};

  // The connection the ViewModel was given (the singleton in the app, a fake in tests)
  @override
  bool get hasConnection => _connectivity.isOnline;

  int? get userId => _userId;
  bool get isLoading => _isLoading;
  bool get isSubmitting => _isSubmitting;
  String? get error => _error;
  MatchHistoryFilter get filter => _filter;
  List<MatchHistoryItem> get all => _result.all;
  bool get isEmpty => _result.all.isEmpty;
  double? get averageReceived => _result.averageReceived;
  int get pendingToRate => _result.pendingToRate;
  int get ratedCount => _result.rated.length;

  // The matches of the selected chip
  List<MatchHistoryItem> get items {
    switch (_filter) {
      case MatchHistoryFilter.toRate:
        return _result.toRate;
      case MatchHistoryFilter.rated:
        return _result.rated;
      case MatchHistoryFilter.all:
        return _result.all;
    }
  }

  // My rating of this match waits in the outbox: it shows "Pendiente de enviar" and cannot be rated again
  bool isPending(int matchId) {
    final userId = _userId;
    return userId != null && _pendingKeys.contains(MatchRatingOutbox.key(userId, matchId));
  }

  // True when the "Calificar" button must show
  bool canRateNow(MatchHistoryItem item) => item.canRate && item.myRating == null && !isPending(item.matchId);

  // Message for a SnackBar (queued, sent, refused). It is read once.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  void selectFilter(MatchHistoryFilter filter) {
    if (_filter == filter) return;
    _filter = filter;
    _notify();
  }

  // Loads the history when the screen opens. It reloads by itself when the connection comes back and
  // when a queued rating leaves the outbox.
  Future<void> init() async {
    listenToConnectivity(onRestored: () => refresh(force: true));
    try {
      _userId = await _readUserId();
    } catch (e) {
      debugPrint('No se pudo leer el usuario: $e');
    }
    _watchOutbox();
    return refresh();
  }

  Future<void> pullToRefresh() => refresh(force: true);

  void _logCache(String result) => debugPrint('$result mis matches ${_cache.describe()}');

  // Memory (LRU) → SQLite → network - GET /matches/user/{userId}/history.
  // A fresh LRU entry is enough. On a miss the history saved in SQLite is shown at once and, with
  // connection, the network refreshes it. Without connection (or if the call fails or is too slow)
  // the SQLite history stays. force skips the LRU (pull to refresh, connection back, rating sent).
  Future<void> refresh({bool force = false}) async {
    // Estrategia: Multithreading (guard _loadSeq). The last load to START wins: an answer that
    // arrives after a newer load began is ignored.
    final seq = ++_loadSeq;
    _isLoading = !_hasLoaded;
    _error = null;
    _notify();

    try {
      final userId = _userId ?? await _readUserId();
      _userId = userId;
      if (seq != _loadSeq) return;
      if (userId == null) {
        _error = 'No hay una sesión activa';
        return;
      }

      if (!force) {
        final cached = _cache.get(userId);
        if (cached != null) {
          _logCache('ACIERTO');
          final pending = await _readPendingRatings(userId);
          final result = await _process(MatchHistoryPayload(items: cached, pending: pending));
          if (seq != _loadSeq) return;
          _pendingRatings = pending;
          _apply(result);
          // A memory hit without connection is still old data: the banner must show
          if (hasConnection) {
            markFresh();
          } else {
            markFromCache(lastUpdated ?? await _safe<DateTime?>(() => _dao.lastSavedAt(userId)));
          }
          return;
        }
        _logCache('FALLO');
        if (!_hasLoaded && hasConnection) await _loadSaved(userId, seq);
        if (seq != _loadSeq) return;
        _isLoading = !_hasLoaded;
        _notify();
      }

      if (hasConnection) {
        // A timeout does not cancel the request: once we gave up on it, its late answer is ignored
        var abandoned = false;
        bool stillCurrent() => !abandoned && seq == _loadSeq;
        try {
          await _loadFromNetwork(userId, stillCurrent).timeout(OfflineAwareMixin.loadTimeout);
          if (!stillCurrent()) return;
          markFresh();
          return;
        } catch (e) {
          abandoned = true;
          if (seq != _loadSeq) return;
          debugPrint('Sin red para mis matches, se usa lo guardado: $e');
          if (!await _loadSaved(userId, seq)) rethrow;
          return;
        }
      }

      // Estrategia: Eventual connectivity. Offline the history saved in SQLite is shown with the banner
      if (!await _loadSaved(userId, seq) && seq == _loadSeq) {
        _error = 'Sin conexión y aún no tenemos tus matches guardados';
      }
    } catch (e) {
      if (seq == _loadSeq) {
        _error = userMessage(e, network: 'No pudimos conectar con el servidor para cargar tus matches');
      }
    } finally {
      if (seq == _loadSeq) {
        _isLoading = false;
        _notify();
      }
    }
  }

  Future<void> _loadFromNetwork(int userId, bool Function() stillCurrent) async {
    // Estrategia: Multithreading (Future.wait). The history and the ratings waiting in the outbox are
    // read at the same time, then parsed and grouped in another isolate (Isolate.run).
    final results = await Future.wait<Object>([
      _service.getHistory(userId),
      _readPendingRatings(userId),
    ]);
    if (!stillCurrent()) return;

    final pending = results[1] as Map<int, MatchRating>;
    final result = await _process(MatchHistoryPayload(body: results[0] as String, pending: pending));
    if (!stillCurrent()) return;

    _pendingRatings = pending;
    _apply(result);
    _cache.put(userId, result.serverItems);
    // Saved for the next time without internet; not awaited, it never breaks the screen
    _saveHistory(userId, result.serverItems);
  }

  // Shows the history saved in SQLite; returns false if nothing was saved for this user
  Future<bool> _loadSaved(int userId, int seq) async {
    try {
      final saved = await _dao.getAllForUser(userId);
      if (saved.isEmpty) return false;
      final savedAt = await _dao.lastSavedAt(userId);
      final pending = await _readPendingRatings(userId);
      final result = await _process(MatchHistoryPayload(items: saved, pending: pending));
      if (seq != _loadSeq) return true;

      _pendingRatings = pending;
      _apply(result);
      markFromCache(savedAt);
      return true;
    } catch (e) {
      debugPrint('No se pudo leer el historial guardado: $e');
      return false;
    }
  }

  void _apply(MatchHistoryResult result) {
    _result = result;
    _base = result.serverItems;
    _hasLoaded = true;
  }

  // Groups again after a local change (a rating queued, sent or refused), without the network
  Future<void> _reprocess() async {
    final result = await _process(MatchHistoryPayload(items: _base, pending: Map.of(_pendingRatings)));
    if (_disposed) return;
    _result = result;
    _notify();
  }

  void _saveHistory(int userId, List<MatchHistoryItem> items) {
    _dao.replaceAllForUser(userId, items).catchError((Object e) {
      debugPrint('No se pudo guardar el historial: $e');
    });
  }

  // The ratings of this user that wait in the outbox (matchId -> rating), read from their saved body
  Future<Map<int, MatchRating>> _readPendingRatings(int userId) async {
    final pending = <int, MatchRating>{};
    try {
      final actions = await _outbox.pendingActions();
      for (final action in actions) {
        final key = action.key;
        if (action.type != MatchRatingOutbox.type || key == null) continue;
        final matchId = MatchRatingOutbox.matchIdOf(key, userId);
        if (matchId == null) continue;

        final body = await _outbox.pendingBody(key);
        if (body == null) continue;
        final json = jsonDecode(body) as Map<String, dynamic>;
        pending[matchId] = MatchRating(
          stars: (json['stars'] as num).toInt(),
          comment: json['comment'] as String?,
        );
      }
    } catch (e) {
      debugPrint('No se pudieron leer las calificaciones pendientes: $e');
    }
    return pending;
  }

  // Rates a completed match - POST /matches/{matchId}/ratings {stars, comment}
  // Returns null when it was sent or queued (see takeNotice), or the error message.
  Future<String?> rate(int matchId, int stars, String? comment) async {
    final userId = _userId;
    if (userId == null) return 'No hay una sesión activa';
    if (stars < 1 || stars > 5) return 'Elige de 1 a 5 estrellas';
    final text = comment?.trim() ?? '';
    if (text.length > maxComment) return 'El comentario no puede tener más de $maxComment caracteres';

    final item = _find(matchId);
    if (item == null) return 'No encontramos este match';
    // No double rating: already rated, already waiting in the outbox, or a send in progress
    if (_isSubmitting || item.myRating != null || isPending(matchId)) return alreadyRated;
    if (!item.canRate) return 'Este match aún no se puede calificar';

    final rating = MatchRating(stars: stars, comment: text.isEmpty ? null : text);
    _isSubmitting = true;
    _notify();
    try {
      if (!hasConnection) {
        await _queue(userId, item, rating);
        return null;
      }

      try {
        await _service.rate(matchId, stars, text).timeout(OfflineAwareMixin.loadTimeout);
        await _onSent(userId, matchId, rating);
        return null;
      } catch (e) {
        // A send that timed out may have reached the back: the outbox sends it again and a 409 counts as done
        if (isNetworkError(e)) {
          await _queue(userId, item, rating);
          return null;
        }
        return userMessage(e, network: 'No se pudo enviar tu calificación. Intenta de nuevo.');
      }
    } catch (e) {
      debugPrint('No se pudo guardar la calificación: $e');
      return 'No se pudo guardar tu calificación. Intenta de nuevo.';
    } finally {
      _isSubmitting = false;
      _notify();
    }
  }

  MatchHistoryItem? _find(int matchId) {
    for (final item in _base) {
      if (item.matchId == matchId) return item;
    }
    return null;
  }

  // Estrategia: Eventual connectivity (SQLite outbox). The rating is saved in the outbox with the key
  // match_rating:<userId>:<matchId> and sent by itself when the internet comes back. The dedupe key
  // leaves a single row however many times the user taps. Until then it shows as "Pendiente de enviar".
  Future<void> _queue(int userId, MatchHistoryItem item, MatchRating rating) async {
    final key = MatchRatingOutbox.key(userId, item.matchId);
    await _outbox.enqueue(
      type: MatchRatingOutbox.type,
      method: 'POST',
      endpoint: MatchRatingOutbox.endpoint(item.matchId),
      body: MatchRatingOutbox.body(rating.stars, rating.comment),
      dedupeKey: key,
      label: item.otherUser?.name,
    );
    _pendingKeys = {..._pendingKeys, key};
    _pendingRatings = {..._pendingRatings, item.matchId: rating};
    _notice = queuedNotice;
    await _reprocess();
  }

  // The back stored the rating: the draft is removed and the history keeps it at once
  Future<void> _onSent(int userId, int matchId, MatchRating rating) async {
    await _safe(() => _drafts.delete(userId, matchId));
    final confirmed = MatchRating(stars: rating.stars, comment: rating.comment, createdAt: DateTime.now());
    _base = _base.map((i) => i.matchId == matchId ? i.withMyRating(confirmed) : i).toList();
    _cache.put(userId, _base);
    _saveHistory(userId, _base);
    _notice = sentNotice;
    await _reprocess();
    // Brings the rating of the other student, which the back only shows once I rated
    refresh(force: true);
  }

  void _watchOutbox() {
    try {
      _pendingSub = _outbox.pendingKeys.listen((keys) {
        final userId = _userId;
        if (userId == null) return;
        final prefix = MatchRatingOutbox.prefix(userId);
        final mine = keys.where((k) => k.startsWith(prefix)).toSet();
        final left = _pendingKeys.difference(mine);
        _pendingKeys = mine;
        _notify();
        if (left.isNotEmpty) _onRatingsLeft(userId, left);
      }, onError: (Object e) => debugPrint('Error watching the outbox: $e'));
    } catch (e) {
      debugPrint('No se pudo vigilar la cola de envío: $e');
    }
  }

  // A queued rating left the outbox: it was sent, unless the back refused it (lastRefusalFor) or it ran
  // out of attempts. A refused rating goes back to "Por calificar" and the user is told why.
  Future<void> _onRatingsLeft(int userId, Set<String> left) async {
    for (final key in left) {
      // An old emission of the stream can arrive late: only a key that is really gone counts
      if (await _safe(() => _outbox.isPending(key)) == true) continue;
      final matchId = MatchRatingOutbox.matchIdOf(key, userId);
      if (matchId == null) continue;

      final rating = _pendingRatings[matchId];
      _pendingRatings = Map.of(_pendingRatings)..remove(matchId);

      final refusal = await _safe(() => _outbox.lastRefusalFor(key));
      if (refusal != null) {
        _notice = 'No se pudo enviar tu calificación: ${refusal.message}';
      } else if (await _safe(() => _outbox.isExhausted(key)) == true) {
        _notice = 'No se pudo enviar tu calificación. Intenta de nuevo.';
      } else if (rating != null) {
        await _onSent(userId, matchId, rating);
        continue;
      }
    }
    if (_disposed) return;
    _cache.remove(userId);
    await _reprocess();
    refresh(force: true);
  }

  // The draft of the rating sheet of a match (null if there is none)
  Future<RatingDraft?> loadDraft(int matchId) async {
    final userId = _userId;
    if (userId == null) return null;
    return _safe<RatingDraft?>(() => _drafts.load(userId, matchId));
  }

  // Saves what the user is writing in the sheet, so it is not lost if the sheet or the app closes
  Future<void> saveDraft(int matchId, int stars, String comment) async {
    final userId = _userId;
    if (userId == null) return;
    await _safe(() => _drafts.save(userId, matchId, RatingDraft(stars: stars, comment: comment)));
  }

  Future<T?> _safe<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (_) {
      return null;
    }
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
