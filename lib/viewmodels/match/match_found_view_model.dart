import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/responses/match_candidate.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// Best candidate found and the action to send the match request.
// The candidate is already on the device, so the screen works without internet; connecting
// without internet is queued in the outbox.
class MatchFoundViewModel extends ChangeNotifier with OfflineAwareMixin {
  static const offlineNotice = 'Se enviará cuando vuelva la conexión';
  static const offlineBanner = 'Sin conexión · tu solicitud se enviará cuando vuelva';
  static const slowNotice = 'Está tardando más de lo normal; tu solicitud se enviará cuando se pueda';
  static const refusedNotice = 'No se pudo enviar la solicitud. Elige otro candidato';
  static const unconfirmedNotice = 'No pudimos confirmar que tu solicitud llegó. Intenta de nuevo';

  final int userId;
  final int currentGapId;
  final MatchCandidate candidate;
  final MatchModeEnum selectedMode;
  final MatchService _matchService;
  final MiguelLocalCache _localCache;
  final OutboxService? _outbox;

  MatchFoundViewModel({
    required this.userId,
    required this.currentGapId,
    required this.candidate,
    required this.selectedMode,
    MatchService? matchService,
    MiguelLocalCache? localCache,
    this._outbox,
  })  : _matchService = matchService ?? MatchService(),
        _localCache = localCache ?? MiguelLocalCache.instance;

  bool _isLoading = false;
  String? _errorMessage;
  String? _notice;
  bool _wasSent = false;
  String? _refusalMessage;
  String? _outcomeMessage;
  bool _disposed = false;
  Set<String> _pendingKeys = {};
  StreamSubscription<Set<String>>? _pendingSub;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // The request waits in the outbox: the button is off and says "Pendiente de enviar".
  // The key has the two gaps because the match does not exist until the back creates it.
  String get connectKey => 'match_connect:$currentGapId-${candidate.acceptorGap.id}';
  bool get isConnectPending => _pendingKeys.contains(connectKey);

  // The queued request reached the back (confirmed with the matches of the user)
  bool get wasSent => _wasSent;

  // The back refused the queued request: the screen offers to choose another candidate
  String? get refusalMessage => _refusalMessage;

  // What the screen shows about the queued request when it did not work
  String? get outcomeMessage => _outcomeMessage;

  // Message for the View after connect() when nothing failed but nothing was sent yet. It is read once.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  // Starts listening to the connection and to the outbox (the candidate needs no loading)
  void init() {
    listenToConnectivity(onRestored: () async {});
    try {
      _pendingSub = (_outbox ?? OutboxService.instance).pendingKeys.listen((keys) {
        // The key left the outbox: it can be because the back accepted it, refused it or it was dropped
        final left = _pendingKeys.contains(connectKey) && !keys.contains(connectKey);
        _pendingKeys = keys;
        if (left) _resolveQueuedConnect();
        _notify();
      }, onError: (e) => debugPrint('Error watching the outbox: $e'));
    } catch (e) {
      debugPrint('Could not watch the outbox: $e');
    }
  }

  // Sends the match request - POST /matches/request
  // Returns the created match, or null on error (see errorMessage) or when it was queued (see takeNotice)
  Future<Match?> connect() async {
    if (isConnectPending) {
      _notice = 'Pendiente de enviar';
      return null;
    }

    _isLoading = true;
    _errorMessage = null;
    _outcomeMessage = null;
    _notify();

    try {
      if (!hasConnection) return await _queue();

      // Estrategia: Future con handler. .then runs when the request works (it saves the candidate
      // that was shown, with the id of its match); .catchError runs when it fails: a network error
      // queues the request and any other error goes to the catch below.
      return await _matchService
          .sendRequest(currentGapId, candidate.acceptorGap.id, candidate.score)
          .timeout(OfflineAwareMixin.loadTimeout)
          .then<Match?>((match) {
        _localCache.saveSeenCandidate(match.id, candidate);
        return match;
      }).catchError((Object e) {
        if (!isNetworkError(e)) throw e;
        // A slow answer is not the same as no connection: the request may already exist in the back
        if (e is TimeoutException) return _afterTimeout();
        return _queue();
      });
    } catch (e) {
      _errorMessage = 'Error: ${e.toString().replaceAll('Exception: ', '')}';
      return null;
    } finally {
      // The spinner only stops when there is no match; on success the screen is replaced
      _isLoading = false;
      _notify();
    }
  }

  // The request took too long. The back may have created the match anyway, and queueing it would only
  // end in a 409, so the matches of the user are asked first: if the request is there, it is the answer.
  // If it is not there (or it cannot be asked) it is queued as before.
  Future<Match?> _afterTimeout() async {
    try {
      final existing = await _existingRequest().timeout(OfflineAwareMixin.loadTimeout);
      if (existing != null) {
        _localCache.saveSeenCandidate(existing.id, candidate);
        return existing;
      }
    } catch (e) {
      debugPrint('Could not check the request after the timeout: $e');
    }
    final queued = await _queue();
    _notice = slowNotice;
    return queued;
  }

  // Takes the queued request out of the outbox so it is never sent when the network returns.
  // With nothing pending it changes nothing.
  Future<void> cancelRequest() async {
    if (!isConnectPending) return;
    // The key is forgotten first: when the outbox reports that it left, it must not look like a sent request
    final before = _pendingKeys;
    _pendingKeys = {...before}..remove(connectKey);
    _notify();
    try {
      await (_outbox ?? OutboxService.instance).cancelPending(connectKey);
      _localCache.forgetQueuedCandidate(currentGapId, candidate);
    } catch (e) {
      debugPrint('Could not cancel the pending request: $e');
      _pendingKeys = before;
      _notify();
    }
  }

  // The queued request left the outbox. Leaving does not mean the back accepted it (it also deletes the
  // row when it refuses it), so "sent" is only set after the back says the request exists.
  Future<void> _resolveQueuedConnect() async {
    final refusal = await _lastRefusal();
    if (_disposed) return;
    if (refusal != null) {
      _refusalMessage = refusal.message;
      _outcomeMessage = refusal.message;
      _notify();
      return;
    }

    // GET /matches/user/{userId}: the match if the user has that request, null if not; if it cannot be
    // asked, nothing is known
    Match? existing;
    var known = true;
    try {
      existing = await _existingRequest();
    } catch (e) {
      known = false;
      debugPrint('Could not confirm the match request: $e');
    }
    if (_disposed) return;

    if (existing != null) {
      _wasSent = true;
      // Now the candidate has its match id: it replaces the one saved while the request was queued
      _localCache.saveSeenCandidate(existing.id, candidate);
      _localCache.forgetQueuedCandidate(currentGapId, candidate);
    } else if (known) {
      _refusalMessage = refusedNotice;
      _outcomeMessage = refusedNotice;
    } else {
      _outcomeMessage = unconfirmedNotice;
    }
    _notify();
  }

  Future<OutboxRefusal?> _lastRefusal() async {
    try {
      return await (_outbox ?? OutboxService.instance).lastRefusalFor(connectKey);
    } catch (_) {
      return null;
    }
  }

  // The request of this screen in the matches of the user (null if there is none); throws if they cannot be read
  Future<Match?> _existingRequest() async {
    final matches = await _matchService.getUserMatches(userId);
    for (final m in matches) {
      if (m.proposerGapId == currentGapId &&
          m.acceptorGapId == candidate.acceptorGap.id &&
          m.status != MatchStatusEnum.REJECTED) {
        return m;
      }
    }
    return null;
  }

  // The dedupeKey lets only one request wait in the outbox, so many taps send it once
  Future<Match?> _queue() async {
    await (_outbox ?? OutboxService.instance).enqueue(
      type: 'match_connect',
      method: 'POST',
      endpoint: MatchService.requestEndpoint(currentGapId, candidate.acceptorGap.id, candidate.score),
      dedupeKey: connectKey,
    );
    // The candidate is saved now too, not only when the request works online
    _localCache.saveQueuedCandidate(currentGapId, candidate);
    _pendingKeys = {..._pendingKeys, connectKey};
    _notice = offlineNotice;
    return null;
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
