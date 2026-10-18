import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/services/open_table_participant_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';

// State and logic of the open table detail screen
class OpenTableDetailViewModel extends ChangeNotifier {
  final int openTableId;
  final OpenTableService _openTableService;
  final OpenTableParticipantService _participantService;

  OpenTableDetailViewModel(
    this.openTableId, {
    OpenTableService? openTableService,
    OpenTableParticipantService? participantService,
  })  : _openTableService = openTableService ?? OpenTableService(),
        _participantService = participantService ?? OpenTableParticipantService();

  OpenTable? _table;
  List<OpenTableParticipant> _participants = [];
  int? _currentUserId;
  bool _isMember = false;
  bool _isJoining = false;
  bool _isLoading = true;
  String? _loadError;
  bool _disposed = false;

  OpenTable? get table => _table;
  List<OpenTableParticipant> get participants => _participants;
  bool get isMember => _isMember;
  bool get isJoining => _isJoining;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  bool get isCreator => _table?.creator?.id == _currentUserId;

  bool get isFull =>
      _table!.status != OpenTableStatusEnum.OPEN ||
      _participants.length >= _table!.maxParticipants;

  int get remainingMinutes => _table!.endTime.difference(DateTime.now()).inMinutes;

  // The back does not allow joining or leaving once the end time has passed
  bool get hasEnded => !_table!.endTime.isAfter(DateTime.now());

  // Load the table when the screen opens
  Future<void> init() => refresh();

  // Load the table and its participants - GET /open-tables/{id}, GET /open-table-participants/table/{tableId}
  // Also used to refresh after join / leave
  Future<void> refresh() async {
    _isLoading = true;
    _loadError = null;
    _notify();

    try {
      _currentUserId = await TokenStorage.getUserId();

      final results = await Future.wait([
        _openTableService.getOpenTable(openTableId),
        _participantService.getByOpenTable(openTableId),
      ]);

      _table = results[0] as OpenTable;
      _participants = results[1] as List<OpenTableParticipant>;
      _isMember = _participants.any((p) => p.user?.id == _currentUserId);
    } catch (e) {
      _loadError = '$e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // Join the table - POST /open-table-participants/table/{tableId}/join
  // Returns null when it worked, or the error message; the table is reloaded in both cases
  Future<String?> join() async {
    if (_currentUserId == null) return null;

    _isJoining = true;
    _notify();
    try {
      await _participantService.join(openTableId, _currentUserId!);
      refresh();
      return null;
    } catch (e) {
      refresh();
      return e.toString().replaceAll('Exception: ', '');
    } finally {
      _isJoining = false;
      _notify();
    }
  }

  // Leave the table - DELETE /open-table-participants/table/{tableId}/leave
  // Same return values as join
  Future<String?> leave() async {
    if (_currentUserId == null) return null;

    _isJoining = true;
    _notify();
    try {
      await _participantService.leave(openTableId, _currentUserId!);
      refresh();
      return null;
    } catch (e) {
      refresh();
      return e.toString().replaceAll('Exception: ', '');
    } finally {
      _isJoining = false;
      _notify();
    }
  }

  // True when there is a logged user (join and leave need it)
  bool get hasUser => _currentUserId != null;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
