import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/joel/joel_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/match.dart';
import 'package:gapfinderfrontend_dart/services/match_service.dart';

// What happened with an answer to the invitation
enum InvitationAnswer { done, noSession, failed }

// A match request received: load it, accept it or decline it
class MatchInvitationViewModel extends ChangeNotifier {
  final int matchId;
  final MatchService _matchService;
  final JoelLocalCache _localCache;

  MatchInvitationViewModel(this.matchId, {MatchService? matchService, JoelLocalCache? localCache})
      : _matchService = matchService ?? MatchService(),
        _localCache = localCache ?? JoelLocalCache.instance;

  Match? _match;
  Match? _acceptedMatch;
  bool _isLoading = true;
  bool _isProcessing = false;
  String? _errorMessage;
  bool _disposed = false;

  Match? get match => _match;
  // Match returned by the back after accepting
  Match? get acceptedMatch => _acceptedMatch;
  bool get isLoading => _isLoading;
  bool get isProcessing => _isProcessing;
  String? get errorMessage => _errorMessage;

  // Gets the match and the user who sent it - GET /matches/{id}
  // Returns false if it could not be loaded (the View closes the screen)
  Future<bool> init() async {
    try {
      final match = await _matchService.getById(matchId);
      _match = match;
      _localCache.saveInvitationMatch(match);
      _isLoading = false;
      _notify();
      return true;
    } catch (e) {
      debugPrint('Error loading match invitation: $e');
      return false;
    }
  }

  // Accepts the match - PATCH /matches/{id}/accept
  Future<InvitationAnswer> accept() async {
    if (_match == null) return InvitationAnswer.noSession;
    _isProcessing = true;
    _notify();
    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return InvitationAnswer.noSession;
      _acceptedMatch = await _matchService.accept(_match!.id, userId);
      _localCache.saveInvitationMatch(_acceptedMatch!);
      return InvitationAnswer.done;
    } catch (e) {
      _isProcessing = false;
      _errorMessage = 'Error accepting match: $e';
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
      if (userId == null) return InvitationAnswer.noSession;
      await _matchService.reject(_match!.id, userId);
      return InvitationAnswer.done;
    } catch (e) {
      _isProcessing = false;
      _errorMessage = 'Error declining match: $e';
      _notify();
      return InvitationAnswer.failed;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
