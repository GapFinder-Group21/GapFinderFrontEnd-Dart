import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/outbox_keys.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';

// What happened with an answer to the invitation (queued: saved to be sent when the connection is back)
enum InvitationAnswer { done, queued, noSession, failed }

// A match request received: load it, accept it or decline it.
// Network falling back to cache: the invitation comes from the back or from what was saved.
// Without connection, accept and decline go to the outbox with one key per invitation.
class MatchInvitationViewModel extends ChangeNotifier {
  // The screen never waits longer than this for the back
  static const loadTimeout = Duration(seconds: 15);

  final int matchId;
  final MatchService _matchService;
  final JoelLocalCache _localCache;
  final ConnectivityService _connectivity;
  final OutboxService _outbox;

  MatchInvitationViewModel(
    this.matchId, {
    MatchService? matchService,
    JoelLocalCache? localCache,
    ConnectivityService? connectivity,
    OutboxService? outbox,
  })  : _matchService = matchService ?? MatchService(),
        _localCache = localCache ?? JoelLocalCache.instance,
        _connectivity = connectivity ?? ConnectivityService.instance,
        _outbox = outbox ?? OutboxService.instance;

  StreamSubscription<bool>? _connectivitySub;
  StreamSubscription<Set<String>>? _pendingSub;
  Match? _match;
  Match? _acceptedMatch;
  bool _isLoading = true;
  bool _isProcessing = false;
  bool _isOffline = false;
  bool _unavailable = false;
  bool _isPending = false;
  DateTime? _lastUpdated;
  String? _errorMessage;
  bool _disposed = false;

  Match? get match => _match;
  // Match returned by the back after accepting
  Match? get acceptedMatch => _acceptedMatch;
  bool get isLoading => _isLoading;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;
  bool get isOffline => _isOffline;
  // When the invitation on screen was last updated (the network answer or the saved copy)
  DateTime? get lastUpdated => _lastUpdated;
  // No connection and the invitation was never saved on the device
  bool get unavailable => _unavailable;
  // True if the answer (accept or decline) waits in the outbox
  bool get isPending => _isPending;
  // True when the invitation is not pending anymore (it was answered or it expired)
  bool get isAnswered => _match != null && _match!.status != MatchStatusEnum.PENDING;

  String get _key => OutboxKeys.matchInvitation(matchId);

  // Gets the match and the user who sent it - GET /matches/{id}
  // Returns false if it could not be loaded (the View closes the screen)
  Future<bool> init() async {
    _isOffline = !_connectivity.isOnline;
    _connectivitySub ??= _connectivity.onStatusChange.listen(_onConnectivityChanged);
    _pendingSub ??= _outbox.pendingKeys.listen(_onPendingKeysChanged);
    return _load();
  }

  // From the back if there is connection; if not, or if the network fails, from SQLite
  Future<bool> _load() async {
    Match? loaded;
    DateTime? updated;

    if (!_isOffline) {
      try {
        loaded = await _matchService.getById(matchId).timeout(loadTimeout);
        updated = DateTime.now();
        _localCache.saveInvitationMatch(loaded);
      } catch (e) {
        debugPrint('Error loading match invitation: $e');
        if (!isNetworkError(e)) return false;
      }
    }

    if (loaded == null) {
      final userId = await TokenStorage.getUserId();
      final saved = userId == null
          ? null
          : await _localCache.safeRead('invitation', () async {
              final match = await _localCache.matches.getById(matchId);
              if (match == null) return null;
              return (match, await _localCache.matches.lastSavedAt(userId));
            });

      if (saved == null) {
        // Nothing saved: the View explains it instead of loading forever or closing
        _unavailable = true;
        _isLoading = false;
        _notify();
        return true;
      }
      loaded = saved.$1;
      updated = saved.$2;
    }

    _match = loaded;
    _lastUpdated = updated;
    _unavailable = false;
    _isLoading = false;
    _notify();
    return true;
  }

  // Back online: reload the invitation by itself
  void _onConnectivityChanged(bool online) {
    _isOffline = !online;
    _notify();
    if (online && !_isProcessing) _load();
  }

  // When the answer leaves the outbox (it was sent) the invitation is reloaded
  void _onPendingKeysChanged(Set<String> keys) {
    final pending = keys.contains(_key);
    final wasPending = _isPending;
    _isPending = pending;
    _notify();
    if (wasPending && !pending) _load();
  }

  // "Reintentar" when the invitation is not available: checks the connection and reloads
  Future<void> retry() async {
    _isLoading = true;
    _notify();
    await _connectivity.checkNow();
    _isOffline = !_connectivity.isOnline;
    final ok = await _load();
    if (!ok) {
      // The back refused it (not a network problem): do not leave the spinner on
      _unavailable = true;
      _isLoading = false;
      _notify();
    }
  }

  // Accepts the match - PATCH /matches/{id}/accept
  Future<InvitationAnswer> accept() async {
    if (_match == null) return InvitationAnswer.noSession;
    _isProcessing = true;
    _notify();
    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) {
        _isProcessing = false;
        _notify();
        return InvitationAnswer.noSession;
      }

      final endpoint = '/matches/${_match!.id}/accept?userId=$userId';
      if (_isOffline) return await _queue(OutboxTypes.matchInvitationAccept, endpoint);

      try {
        _acceptedMatch = await _matchService.accept(_match!.id, userId);
        _localCache.saveInvitationMatch(_acceptedMatch!);
        return InvitationAnswer.done;
      } catch (e) {
        if (isNetworkError(e)) return await _queue(OutboxTypes.matchInvitationAccept, endpoint);
        rethrow;
      }
    } catch (e) {
      _isProcessing = false;
      _errorMessage = userMessage(e, network: 'No pudimos aceptar la invitación. Intenta de nuevo');
      _notify();
      return InvitationAnswer.failed;
    }
  }

  // Declines the match - PATCH /matches/{id}/reject
  Future<InvitationAnswer> decline() async {
    if (_match == null) return InvitationAnswer.noSession;
    _isProcessing = true;
    _notify();
    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) {
        _isProcessing = false;
        _notify();
        return InvitationAnswer.noSession;
      }

      final endpoint = '/matches/${_match!.id}/reject?userId=$userId';
      if (_isOffline) return await _queue(OutboxTypes.matchInvitationDecline, endpoint);

      try {
        await _matchService.reject(_match!.id, userId);
        return InvitationAnswer.done;
      } catch (e) {
        if (isNetworkError(e)) return await _queue(OutboxTypes.matchInvitationDecline, endpoint);
        rethrow;
      }
    } catch (e) {
      _isProcessing = false;
      _errorMessage = userMessage(e, network: 'No pudimos rechazar la invitación. Intenta de nuevo');
      _notify();
      return InvitationAnswer.failed;
    }
  }

  // Saves the answer in the outbox. Accept and decline share the key, so only one answer can be
  // pending per invitation and tapping many times leaves a single action.
  Future<InvitationAnswer> _queue(String type, String endpoint) async {
    await _outbox.enqueue(type: type, method: 'PATCH', endpoint: endpoint, dedupeKey: _key);
    _isPending = true; // the buttons change at once, the stream confirms it
    _isProcessing = false;
    _notify();
    return InvitationAnswer.queued;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _connectivitySub?.cancel();
    _pendingSub?.cancel();
    super.dispose();
  }
}
