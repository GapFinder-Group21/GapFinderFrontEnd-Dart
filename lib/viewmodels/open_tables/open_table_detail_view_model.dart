import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/cache/expiry_policy.dart';
import 'package:gapfinderfrontend_dart/core/cache/lru_cache.dart';
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

// What the detail screen needs from one open table: the table and who is in it
class OpenTableDetailData {
  final OpenTable table;
  final List<OpenTableParticipant> participants;
  OpenTableDetailData(this.table, this.participants);
}

// State and logic of the open table detail screen
class OpenTableDetailViewModel extends ChangeNotifier with OfflineAwareMixin {
  // One cache shared by every detail screen. Memory first, then SQLite, then the network.
  // 20 entries: in one gap a student looks at a handful of tables (about 5 to 10, going back and
  // forth between them), so 20 covers a whole session.
  // The life of an entry depends on the table (see detailExpiry): at most 5 minutes because people
  // join and leave all the time, less if the table is about to end, 15 minutes if it already finished.
  static final LruCache<int, OpenTableDetailData> _cache = LruCache<int, OpenTableDetailData>(
    maxEntries: 20,
    name: 'detalle mesa',
    expiryPolicy: ValueBasedExpiry<int, OpenTableDetailData>(
      (_, data) => detailExpiry(data, DateTime.now()),
    ),
  );

  static const _maxLife = Duration(minutes: 5);
  static const _minLife = Duration(seconds: 30);
  static const _completedLife = Duration(minutes: 15);

  // How long a saved detail is trusted
  @visibleForTesting
  static Duration? detailExpiry(OpenTableDetailData data, DateTime now) {
    // A completed table does not change anymore
    if (data.table.status == OpenTableStatusEnum.COMPLETED) return _completedLife;

    final untilEnd = data.table.endTime.difference(now);
    final life = untilEnd < _maxLife ? untilEnd : _maxLife;
    return life < _minLife ? _minLife : life;
  }

  // Empties the shared cache: used when the session ends (the details belong to the previous user's session)
  // and by the tests, which share it between cases
  static void clearSharedCache() => _cache.clear();

  @visibleForTesting
  static void clearCache() => clearSharedCache();

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
  // A pending join / leave that the back refused when it was finally sent
  String? _syncError;
  // Pending actions the user cancelled by hand: their key leaving the outbox is not a failure
  final Set<String> _cancelledKeys = {};

  // The user id is part of the keys: a pending action of one user is never shown to (or cancelled by) the next one
  String get _joinKey => 'open_table_join:${_currentUserId ?? ''}:$openTableId';
  String get _leaveKey => 'open_table_leave:${_currentUserId ?? ''}:$openTableId';

  OpenTable? get table => _table;
  List<OpenTableParticipant> get participants => _participants;
  bool get isMember => _isMember;
  bool get isJoining => _isJoining;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  String? get syncError => _syncError;

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
  Future<void> init() async {
    listenToConnectivity(onRestored: () => refresh(force: true));
    // The keys of the pending actions need the user id, so it is read before watching the outbox
    try {
      _currentUserId = await TokenStorage.getUserId();
    } catch (e) {
      debugPrint('No se pudo leer el usuario: $e');
    }
    _watchOutbox();
    return refresh();
  }

  void _logCache(String result) => debugPrint('$result mesa $openTableId ${_cache.describe()}');

  void _watchOutbox() {
    try {
      _pendingSub = OutboxService.instance.pendingKeys.listen((keys) {
        final left = {_joinKey, _leaveKey}.where((k) => _pendingKeys.contains(k) && !keys.contains(k)).toSet();
        _pendingKeys = keys;
        _notify();
        if (left.isNotEmpty) {
          _cache.remove(openTableId);
          refresh(force: true).then((_) => _checkSyncResult(left));
        }
      }, onError: (e) => debugPrint('Error watching the outbox: $e'));
    } catch (e) {
      debugPrint('No se pudo vigilar la cola de envío: $e');
    }
  }

  // After a pending action left the outbox and the table was reloaded: if the user is still not a
  // member (join) or still is one (leave), the back refused it (full table, ended...) and the user
  // must be told, because nobody was looking at the screen when it was sent.
  // The outbox keeps the reason the back gave (lastRefusalFor): it is the text shown to the user.
  Future<void> _checkSyncResult(Set<String> left) async {
    final cancelled = left.intersection(_cancelledKeys);
    _cancelledKeys.removeAll(left);
    if (_table == null || cancelled.isNotEmpty) return;

    for (final key in left) {
      final refusal = await _lastRefusal(key);
      if (refusal != null) {
        _syncError = refusal.message;
        _notify();
        return;
      }
    }

    if (left.contains(_joinKey) && !_isMember) {
      _syncError = 'No se pudo unir a la mesa (puede estar llena o haber terminado)';
    } else if (left.contains(_leaveKey) && _isMember) {
      _syncError = 'No se pudo salir de la mesa';
    }
    _notify();
  }

  Future<OutboxRefusal?> _lastRefusal(String key) async {
    try {
      return await OutboxService.instance.lastRefusalFor(key);
    } catch (_) {
      return null;
    }
  }

  // Memory (LRU) → SQLite → network: loads the table and its participants - GET /open-tables/{id},
  // GET /open-table-participants/table/{tableId}. A fresh LRU entry is enough. On a miss the detail
  // saved in SQLite is shown at once (if there is one) and, with connection, the network refreshes it.
  // Without connection (or if the call fails or is too slow) the SQLite detail stays.
  // force skips the LRU: used after join / leave and when the connection comes back.
  Future<void> refresh({bool force = false}) async {
    // The last load to START wins: a result that arrives after a newer load began is ignored
    final seq = ++_loadSeq;
    _isLoading = _table == null;
    _loadError = null;
    _notify();

    try {
      _currentUserId = await TokenStorage.getUserId();
      if (seq != _loadSeq) return;

      if (!force) {
        final cached = _cache.get(openTableId);
        if (cached != null) {
          _logCache('ACIERTO');
          _table = cached.table;
          _participants = cached.participants;
          _isMember = _participants.any((p) => p.user?.id == _currentUserId);
          // A memory hit without connection is still old data: the banner must show
          if (hasConnection) {
            markFresh();
          } else {
            markFromCache(lastUpdated);
          }
          return;
        }
        _logCache('FALLO');
        if (_table == null && hasConnection) await _loadSaved();
        if (seq != _loadSeq) return;
        _isLoading = _table == null;
        _notify();
      }

      if (hasConnection) {
        // A timeout does not cancel the request: once we gave up on it, its late answer is ignored
        var abandoned = false;
        bool stillCurrent() => !abandoned && seq == _loadSeq;
        try {
          await _loadFromNetwork(stillCurrent).timeout(OfflineAwareMixin.loadTimeout);
          if (!stillCurrent()) return;
          markFresh();
          return;
        } catch (e) {
          abandoned = true;
          if (seq != _loadSeq) return;
          debugPrint('Sin red para el detalle, se usa lo guardado: $e');
          if (!await _loadSaved()) rethrow;
          return;
        }
      }

      if (!await _loadSaved() && seq == _loadSeq) {
        _loadError = 'Sin conexión y aún no tenemos esta mesa guardada';
      }
    } catch (e) {
      if (seq == _loadSeq) {
        _loadError = userMessage(e, network: 'No pudimos conectar con el servidor para cargar esta mesa');
      }
    } finally {
      if (seq == _loadSeq) {
        _isLoading = false;
        _notify();
      }
    }
  }

  int _loadSeq = 0;

  Future<void> _loadFromNetwork(bool Function() stillCurrent) async {
    final results = await Future.wait([
      _openTableService.getOpenTable(openTableId),
      _participantService.getByOpenTable(openTableId),
    ]);
    if (!stillCurrent()) return;

    _table = results[0] as OpenTable;
    _participants = results[1] as List<OpenTableParticipant>;
    _isMember = _participants.any((p) => p.user?.id == _currentUserId);

    _cache.put(openTableId, OpenTableDetailData(_table!, _participants));

    // Save the detail the network answered; it is not awaited and never breaks the screen
    SofiaLocalCache.instance.saveOpenTableDetail(_table!, _participants);
    // A table the user is not in any more must not stay in the saved "My open tables"
    if (!_isMember) {
      SofiaLocalCache.instance.removeFromMyTables(openTableId);
    }
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

    // The participants are about to change, so the saved copy in memory is no longer right
    _cache.remove(openTableId);

    _syncError = null;
    _isJoining = true;
    _notify();
    try {
      if (_pendingKeys.contains(oppositeKey) || await _isPending(oppositeKey)) {
        _cancelledKeys.add(oppositeKey);
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
        await send(userId).timeout(OfflineAwareMixin.loadTimeout);
        _cache.remove(openTableId);
        refresh(force: true);
        return null;
      } catch (e) {
        if (isNetworkError(e)) {
          await _queue(key: key, type: type, method: method, endpoint: endpoint(userId));
          return null;
        }
        refresh(force: true);
        return userMessage(e, network: 'No se pudo completar la acción. Intenta de nuevo.');
      }
    } finally {
      _isJoining = false;
      _notify();
    }
  }

  // Cancels the join / leave that is waiting in the outbox, without asking to leave the table
  Future<void> cancelPendingAction() async {
    final key = isJoinPending ? _joinKey : (isLeavePending ? _leaveKey : null);
    if (key == null) return;

    _cancelledKeys.add(key);
    _syncError = null;
    try {
      await OutboxService.instance.cancelPending(key);
    } catch (e) {
      debugPrint('No se pudo cancelar la solicitud: $e');
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
