import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_mode_enum.dart';
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
  bool _disposed = false;
  Set<String> _pendingKeys = {};
  StreamSubscription<Set<String>>? _pendingSub;

  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  // The request waits in the outbox: the button is off and says "Pendiente de enviar".
  // The key has the two gaps because the match does not exist until the back creates it.
  String get connectKey => 'match_connect:$currentGapId-${candidate.acceptorGap.id}';
  bool get isConnectPending => _pendingKeys.contains(connectKey);

  // The queued request reached the back
  bool get wasSent => _wasSent;

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
        final sent = _pendingKeys.contains(connectKey) && !keys.contains(connectKey);
        _pendingKeys = keys;
        if (sent) _wasSent = true;
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

  // The dedupeKey lets only one request wait in the outbox, so many taps send it once
  Future<Match?> _queue() async {
    await (_outbox ?? OutboxService.instance).enqueue(
      type: 'match_connect',
      method: 'POST',
      endpoint: MatchService.requestEndpoint(currentGapId, candidate.acceptorGap.id, candidate.score),
      dedupeKey: connectKey,
    );
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
