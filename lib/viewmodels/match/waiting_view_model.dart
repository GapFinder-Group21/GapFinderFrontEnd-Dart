import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/enums/match_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';

// Events sent by the polling
sealed class WaitingEvent {}

// The other person accepted
class MatchAccepted extends WaitingEvent {
  final Match match;
  MatchAccepted(this.match);
}

// The other person declined
class MatchRejected extends WaitingEvent {}

// Waits for the other person to answer the match request.
// The polling needs the back: it pauses without connection (the screen shows the last saved
// status) and resumes by itself when the connection comes back.
class WaitingViewModel extends ChangeNotifier {
  // Each check waits at most this long, so a slow network never piles up requests
  static const pollTimeout = Duration(seconds: 10);

  final int matchId;
  final int requesterId;
  final User? candidateUser;
  final MatchService _matchService;
  final JoelLocalCache _localCache;
  final ConnectivityService _connectivity;

  WaitingViewModel({
    required this.matchId,
    required this.requesterId,
    this.candidateUser,
    MatchService? matchService,
    JoelLocalCache? localCache,
    ConnectivityService? connectivity,
  })  : _matchService = matchService ?? MatchService(),
        _localCache = localCache ?? JoelLocalCache.instance,
        _connectivity = connectivity ?? ConnectivityService.instance;

  // Estrategia: Stream. The polling sends MatchAccepted or MatchRejected here and the View listens
  final _events = StreamController<WaitingEvent>.broadcast();
  Timer? _pollTimer;
  StreamSubscription<bool>? _connectivitySub;
  bool _isOffline = false;
  bool _polling = false;
  MatchStatusEnum? _lastKnownStatus;
  DateTime? _lastUpdated;
  bool _cancelled = false;
  // The match got a final answer (accepted or rejected): nothing is checked or sent again
  bool _finished = false;
  // The app is in the background: the polling does not run
  bool _paused = false;
  bool _isCancelling = false;
  bool _disposed = false;

  Stream<WaitingEvent> get events => _events.stream;
  bool get isOffline => _isOffline;
  // The cancel request is being sent: the button is off
  bool get isCancelling => _isCancelling;
  // Last status of the match we know (from the back, or saved on the device); null if unknown
  MatchStatusEnum? get lastKnownStatus => _lastKnownStatus;
  // When that status was last updated
  DateTime? get lastUpdated => _lastUpdated;

  // Start checking the match status and listen to the connection
  void init() {
    _isOffline = !_connectivity.isOnline;
    _connectivitySub = _connectivity.onStatusChange.listen(_onConnectivityChanged);
    _loadSavedStatus();
    if (!_isOffline) _startPolling();
  }

  // The app went to the background: the polling stops (no data, battery or token refresh behind)
  void pausePolling() {
    _paused = true;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // The app is back: check at once and poll again (only with connection)
  void resumePolling() {
    if (!_paused) return;
    _paused = false;
    if (_cancelled || _disposed || _isOffline || _finished) return;
    _poll();
    _startPolling();
  }

  // Pauses the polling without connection; checks at once and resumes when it is back
  void _onConnectivityChanged(bool online) {
    _isOffline = !online;
    if (online) {
      if (_cancelled || _disposed || _paused || _finished) return;
      _poll();
      _startPolling();
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      _loadSavedStatus();
    }
    _notify();
  }

  // Status saved the last time the back answered (SQLite)
  Future<void> _loadSavedStatus() async {
    final saved = await _localCache.safeRead('waiting match', () async {
      final match = await _localCache.matches.getById(matchId);
      if (match == null) return null;
      final savedAt = await _localCache.matches.savedAtById(matchId);
      return (match.status, savedAt);
    });
    if (saved == null || _disposed || _lastUpdated != null) return;
    _lastKnownStatus = saved.$1;
    _lastUpdated = saved.$2;
    _notify();
  }

  // Checks the match every 3 seconds - GET /matches/{id}.
  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  // Accepted or rejected -> stops and sends an event to the View.
  Future<void> _poll() async {
    if (_cancelled || _disposed || _isOffline || _polling || _paused || _finished) return;
    _polling = true;
    try {
      final Match match = await _matchService.getById(matchId).timeout(pollTimeout);
      if (_cancelled || _disposed || _finished) return;

      _lastKnownStatus = match.status;
      _lastUpdated = DateTime.now();
      _localCache.saveMatchOfUser(requesterId, match);
      _notify();

      if (match.status == MatchStatusEnum.ACCEPTED) {
        _finish();
        _events.add(MatchAccepted(match));
      } else if (match.status == MatchStatusEnum.REJECTED) {
        _finish();
        _events.add(MatchRejected());
      }
    } catch (e) {
      debugPrint('Error polling match status: $e');
    } finally {
      _polling = false;
    }
  }

  // A final answer arrived: the polling stops for good, so the View gets only one event
  void _finish() {
    _finished = true;
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  // "Cancel Request": cancels the request in the back - POST /matches/{id}/cancel
  // Returns null when it was cancelled (the View closes the screen), or the message to show when it could
  // not be cancelled. If the other person already answered, the back refuses it and the polling keeps going,
  // so the answer still arrives.
  Future<String?> cancelRequest() async {
    if (_isOffline) return 'Cancelar la solicitud necesita conexión';
    if (_isCancelling) return null;
    _isCancelling = true;
    _notify();
    try {
      await _matchService.cancel(matchId).timeout(pollTimeout);
      cancel();
      return null;
    } catch (e) {
      debugPrint('Error cancelling the match request: $e');
      return userMessage(e, network: 'No pudimos cancelar la solicitud. Intenta de nuevo');
    } finally {
      _isCancelling = false;
      _notify();
    }
  }

  // Stops waiting (only the polling, the back is not told)
  void cancel() {
    _cancelled = true;
    _pollTimer?.cancel();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  // Stop the timer when leaving the screen
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _connectivitySub?.cancel();
    _events.close();
    super.dispose();
  }
}
