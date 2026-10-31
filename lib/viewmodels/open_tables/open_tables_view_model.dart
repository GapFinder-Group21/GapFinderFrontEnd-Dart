import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_cache_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/services/location_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_participant_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// State and logic of the open tables tab
class OpenTablesViewModel extends ChangeNotifier with OfflineAwareMixin {
  final OpenTableService _openTableService;
  final OpenTableParticipantService _participantService;

  OpenTablesViewModel({
    OpenTableService? openTableService,
    OpenTableParticipantService? participantService,
  })  : _openTableService = openTableService ?? OpenTableService(),
        _participantService = participantService ?? OpenTableParticipantService();

  List<OpenTable> _openTables = [];
  Set<int> _joinedTableIds = {};
  Set<int> _unknownTableIds = {};
  bool _isLoading = true;
  int? _userId;
  String? _errorMessage;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  bool _disposed = false;

  List<OpenTable> get openTables => _openTables;
  bool get isLoading => _isLoading;
  int? get userId => _userId;
  String? get errorMessage => _errorMessage;

  // The error is about the location being off
  bool get isLocationError => _errorMessage?.contains('Location is required') ?? false;

  bool isCreator(OpenTable table) => table.creator?.id == _userId;
  bool isMember(OpenTable table) => _joinedTableIds.contains(table.id);

  // The check of this table failed: we do not know if the user is in it, so the list does not offer Join
  bool isMembershipUnknown(OpenTable table) => _unknownTableIds.contains(table.id);

  // Load the tables; reload them when the GPS is turned on or off and when the connection comes back
  Future<void> init() async {
    listenToConnectivity(onRestored: refresh);
    _listenToLocationChanges();
    await refresh();
  }

  // Reload the list when the GPS is turned on or off
  void _listenToLocationChanges() {
    if (!kIsWeb) {
      _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((status) {
        debugPrint('DEBUG: GPS Status changed to: $status');
        refresh();
      });
    }
  }

  // Every load takes a number. A result that arrives after a newer load started is ignored, so the last
  // one to START wins, not the last one to finish (tab taps, the GPS stream, the connection coming back).
  int _loadSeq = 0;

  // Network falling back to cache: loads the open tables that are still open - GET /open-tables.
  // Without connection (or if the call fails or is too slow) it shows the list saved in SQLite, read only.
  Future<void> refresh() async {
    final seq = ++_loadSeq;
    _isLoading = _openTables.isEmpty;
    _errorMessage = null;
    _notify();

    try {
      final userId = await TokenStorage.getUserId();
      if (seq != _loadSeq) return;
      _userId = userId;
      _notify();
      if (userId == null) return;

      final hasLocation = await LocationService.isLocationEnabled();
      if (seq != _loadSeq) return;
      if (!hasLocation) {
        _errorMessage = 'Location is required to discover tables nearby.';
        _notify();
        return;
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
          debugPrint('Sin red para las mesas, se usa lo guardado: $e');
          if (!await _loadSaved(userId, () => seq == _loadSeq)) rethrow;
          return;
        }
      }

      if (!await _loadSaved(userId, () => seq == _loadSeq)) {
        if (seq == _loadSeq) _errorMessage = 'Sin conexión y aún no tenemos mesas guardadas.';
      }
    } catch (e) {
      if (seq == _loadSeq) {
        _errorMessage = userMessage(e, network: 'No pudimos traer las mesas cercanas, intenta de nuevo');
      }
    } finally {
      if (seq == _loadSeq) {
        _isLoading = false;
        _notify();
      }
    }
  }

  // The list the network answers, and which of those tables the user already joined
  Future<void> _loadFromNetwork(int userId, bool Function() stillCurrent) async {
    final all = await _openTableService.getAll();
    if (!stillCurrent()) return;
    final now = DateTime.now();
    final tables = all
        .where((t) => t.status == OpenTableStatusEnum.OPEN && t.endTime.isAfter(now))
        .toList();

    // Save the list the network answered; it is not awaited and never breaks the screen
    SofiaLocalCache.instance.saveOpenTables(OpenTableListType.all, tables, userId: userId);

    final checks = await Future.wait(tables.map((t) => _isParticipant(t.id, userId)));
    if (!stillCurrent()) return;
    final joinedIds = <int>{};
    final unknownIds = <int>{};
    for (int i = 0; i < tables.length; i++) {
      final isIn = checks[i];
      if (isIn == null) {
        unknownIds.add(tables[i].id);
      } else if (isIn) {
        joinedIds.add(tables[i].id);
      }
    }
    _openTables = tables;
    _joinedTableIds = joinedIds;
    _unknownTableIds = unknownIds;
    _notify();
  }

  // Shows the list saved in SQLite ('ALL'); returns false if nothing was ever saved.
  // A list saved with no tables is a real answer: the screen shows it empty, not "never saved".
  // The tables of the user ('MINE') tell which ones were already joined.
  Future<bool> _loadSaved(int userId, bool Function() stillCurrent) async {
    try {
      final cache = SofiaLocalCache.instance;
      final saved = await cache.openTables.getAll(OpenTableListType.all);
      final savedAt = await cache.savedAt(OpenTableListType.all, userId) ?? await cache.openTables.lastSavedAt(OpenTableListType.all);
      if (saved.isEmpty && savedAt == null) return false;

      final mine = await cache.openTables.getAll(OpenTableListType.mine);
      final details = await cache.openTableDetails.getAll();
      if (!stillCurrent()) return true;

      final now = DateTime.now();
      final joined = mine.map((t) => t.id).toSet();

      // "Mine" is only saved when that screen was opened. The saved details are newer when the user joined or
      // left a table on its detail screen: for each table the newest detail decides.
      for (final d in details) {
        final isIn = d.participants.any((p) => p.user?.id == userId);
        if (isIn) {
          joined.add(d.table.id);
        } else {
          joined.remove(d.table.id);
        }
      }

      _openTables = saved.where((t) => t.endTime.isAfter(now)).toList();
      _joinedTableIds = joined;
      _unknownTableIds = {};
      markFromCache(savedAt);
      return true;
    } catch (e) {
      debugPrint('No se pudieron leer las mesas guardadas: $e');
      return false;
    }
  }

  // Checks if the user already joined a table - GET /open-table-participants/table/{tableId}
  // true / false when the back answered; null when the check failed (unknown, so Join is not offered)
  Future<bool?> _isParticipant(int tableId, int userId) async {
    try {
      final List<OpenTableParticipant> list = await _participantService.getByOpenTable(tableId).timeout(OfflineAwareMixin.loadTimeout);
      return list.any((p) => p.user?.id == userId);
    } catch (_) {
      return null;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  // Stop listening to the GPS when leaving the screen
  void dispose() {
    _disposed = true;
    _serviceStatusSubscription?.cancel();
    super.dispose();
  }
}
