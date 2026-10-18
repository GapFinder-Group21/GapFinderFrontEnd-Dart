import 'dart:async';
import 'package:flutter/foundation.dart';
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

// Waits for the other person to answer the match request
class WaitingViewModel extends ChangeNotifier {
  final int matchId;
  final int requesterId;
  final User? candidateUser;
  final MatchService _matchService;

  WaitingViewModel({
    required this.matchId,
    required this.requesterId,
    this.candidateUser,
    MatchService? matchService,
  }) : _matchService = matchService ?? MatchService();

  final _events = StreamController<WaitingEvent>.broadcast();
  Timer? _pollTimer;
  bool _cancelled = false;
  bool _disposed = false;

  Stream<WaitingEvent> get events => _events.stream;

  // Start checking the match status
  void init() => _startPolling();

  // Checks the match every 3 seconds - GET /matches/{id}.
  // Accepted or rejected -> stops and sends an event to the View.
  void _startPolling() {
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (_cancelled || _disposed) return;
      try {
        final Match match = await _matchService.getById(matchId);
        if (_cancelled || _disposed) return;

        if (match.status == MatchStatusEnum.ACCEPTED) {
          _pollTimer?.cancel();
          _events.add(MatchAccepted(match));
        } else if (match.status == MatchStatusEnum.REJECTED) {
          _pollTimer?.cancel();
          _events.add(MatchRejected());
        }
      } catch (e) {
        debugPrint('Error polling match status: $e');
      }
    });
  }

  // Stops waiting
  void cancel() {
    _cancelled = true;
    _pollTimer?.cancel();
  }

  @override
  // Stop the timer when leaving the screen
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    _events.close();
    super.dispose();
  }
}
