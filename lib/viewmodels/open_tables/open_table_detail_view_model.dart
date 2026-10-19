import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/services/open_table_participant_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// State and logic of the open table detail screen
class OpenTableDetailViewModel extends ChangeNotifier with OfflineAwareMixin {
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
  StreamSubscription<Set<String>>? _pendingSub;
  Set<String> _pendingKeys = {};
  String? _notice;

  String get _joinKey => 'open_table_join:$openTableId';
  String get _leaveKey => 'open_table_leave:$openTableId';

  OpenTable? get table => _table;
  List<OpenTableParticipant> get participants => _participants;
  bool get isMember => _isMember;
  bool get isJoining => _isJoining;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  // A join or a leave is waiting in the outbox: the button is off and says "Pendiente de enviar"
  bool get isJoinPending => _pendingKeys.contains(_joinKey);
  bool get isLeavePending => _pendingKeys.contains(_leaveKey);
  bool get hasPendingAction => isJoinPending || isLeavePending;

  // Message for the View after join() / leave() when nothing failed but nothing was sent yet.
  // It is read once.
  String? takeNotice() {
    final notice = _notice;
    _notice = null;
    return notice;
  }

  bool get isCreator => _table?.creator?.id == _currentUserId;

  bool get isFull =>
      _table!.status != OpenTableStatusEnum.OPEN ||
      _participants.length >= _table!.maxParticipants;

  int get remainingMinutes => _table!.endTime.difference(DateTime.now()).inMinutes;

  // The back does not allow joining or leaving once the end time has passed
  bool get hasEnded => !_table!.endTime.isAfter(DateTime.now());

  // Load the table when the screen opens. It reloads by itself when the connection comes back and
  // when the outbox sends the pending join / leave (the key leaves the pending set).
  Future<void> init() {
    listenToConnectivity(onRestored: refresh);
    _watchOutbox();
    return refresh();
  }

  void _watchOutbox() {
    try {
      _pendingSub = OutboxService.instance.pendingKeys.listen((keys) {
        final sent = {_joinKey, _leaveKey}.any((k) => _pendingKeys.contains(k) && !keys.contains(k));
        _pendingKeys = keys;
        _notify();
        if (sent) refresh();
      }, onError: (e) => debugPrint('Error watching the outbox: $e'));
    } catch (e) {
      debugPrint('No se pudo vigilar la cola de envío: $e');
    }
  }

  // Network falling back to cache: loads the table and its participants - GET /open-tables/{id},
  // GET /open-table-participants/table/{tableId}. Without connection (or if the call fails or is
  // too slow) it shows the detail saved in SQLite. Also used to refresh after join / leave.
  Future<void> refresh() async {
    _isLoading = _table == null;
    _loadError = null;
    _notify();

    try {
      _currentUserId = await TokenStorage.getUserId();

      if (hasConnection) {
        try {
          await _loadFromNetwork().timeout(OfflineAwareMixin.loadTimeout);
          markFresh();
          return;
        } catch (e) {
          debugPrint('Sin red para el detalle, se usa lo guardado: $e');
          if (!await _loadSaved()) rethrow;
          return;
        }
      }

      if (!await _loadSaved()) {
        _loadError = 'Sin conexión y aún no tenemos esta mesa guardada';
      }
    } catch (e) {
      _loadError = '$e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> _loadFromNetwork() async {
    final results = await Future.wait([
      _openTableService.getOpenTable(openTableId),
      _participantService.getByOpenTable(openTableId),
    ]);

    _table = results[0] as OpenTable;
    _participants = results[1] as List<OpenTableParticipant>;
    _isMember = _participants.any((p) => p.user?.id == _currentUserId);

    // Save the detail the network answered; it is not awaited and never breaks the screen
    SofiaLocalCache.instance.saveOpenTableDetail(_table!, _participants);
  }

  // Shows the detail saved in SQLite; returns false if this table was never saved
  Future<bool> _loadSaved() async {
    try {
      final record = await SofiaLocalCache.instance.openTableDetails.getById(openTableId);
      if (record == null) return false;

      _table = record.table;
      _participants = record.participants;
      _isMember = _participants.any((p) => p.user?.id == _currentUserId);
      markFromCache(record.savedAt);
      return true;
    } catch (e) {
      debugPrint('No se pudo leer el detalle guardado: $e');
      return false;
    }
  }

  // Join the table - POST /open-table-participants/table/{tableId}/join
  // Returns null when it worked (or was queued: see takeNotice), or the error message.
  // Without connection the action goes to the outbox; the table is reloaded in every case.
  Future<String?> join() => _act(
        key: _joinKey,
        oppositeKey: _leaveKey,
        type: 'open_table_join',
        method: 'POST',
        endpoint: (userId) => '/open-table-participants/table/$openTableId/join?userId=$userId',
        send: (userId) => _participantService.join(openTableId, userId),
      );

  // Leave the table - DELETE /open-table-participants/table/{tableId}/leave
  // Same return values as join
  Future<String?> leave() => _act(
        key: _leaveKey,
        oppositeKey: _joinKey,
        type: 'open_table_leave',
        method: 'DELETE',
        endpoint: (userId) => '/open-table-participants/table/$openTableId/leave?userId=$userId',
        send: (userId) => _participantService.leave(openTableId, userId),
      );

  // Join and leave work the same way:
  // 1. the opposite action is pending: both cancel each other and nothing is sent
  // 2. the same action is pending: nothing to do (the dedupeKey would refuse it anyway)
  // 3. no connection or the network fails: the action is queued with its dedupeKey
  // 4. connection: it is sent now
  Future<String?> _act({
    required String key,
    required String oppositeKey,
    required String type,
    required String method,
    required String Function(int userId) endpoint,
    required Future<void> Function(int userId) send,
  }) async {
    final userId = _currentUserId;
    if (userId == null) return null;

    _isJoining = true;
    _notify();
    try {
      if (_pendingKeys.contains(oppositeKey) || await _isPending(oppositeKey)) {
        await OutboxService.instance.cancelPending(oppositeKey);
        _notice = 'Se canceló la acción pendiente';
        return null;
      }

      if (_pendingKeys.contains(key)) {
        _notice = 'Pendiente de enviar';
        return null;
      }

      if (!hasConnection) {
        await _queue(key: key, type: type, method: method, endpoint: endpoint(userId));
        return null;
      }

      try {
        await send(userId);
        refresh();
        return null;
      } catch (e) {
        if (isNetworkError(e)) {
          await _queue(key: key, type: type, method: method, endpoint: endpoint(userId));
          return null;
        }
        refresh();
        return e.toString().replaceAll('Exception: ', '');
      }
    } finally {
      _isJoining = false;
      _notify();
    }
  }

  Future<bool> _isPending(String key) async {
    try {
      return await OutboxService.instance.isPending(key);
    } catch (_) {
      return false;
    }
  }

  // The dedupeKey lets only one equal action wait in the outbox, so many taps send it once
  Future<void> _queue({
    required String key,
    required String type,
    required String method,
    required String endpoint,
  }) async {
    await OutboxService.instance.enqueue(type: type, method: method, endpoint: endpoint, dedupeKey: key);
    _pendingKeys = {..._pendingKeys, key};
    _notice = 'Se enviará cuando vuelva la conexión';
  }

  // True when there is a logged user (join and leave need it)
  bool get hasUser => _currentUserId != null;

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
