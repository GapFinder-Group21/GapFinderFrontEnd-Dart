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

  // Network falling back to cache: loads the open tables that are still open - GET /open-tables.
  // Without connection (or if the call fails or is too slow) it shows the list saved in SQLite, read only.
  Future<void> refresh() async {
    _isLoading = _openTables.isEmpty;
    _errorMessage = null;
    _notify();

    try {
      final userId = await TokenStorage.getUserId();
      _userId = userId;
      _notify();
      if (userId == null) return;

      final hasLocation = await LocationService.isLocationEnabled();
      if (!hasLocation) {
        _errorMessage = 'Location is required to discover tables nearby.';
        _notify();
        return;
      }

      if (hasConnection) {
        try {
          await _loadFromNetwork(userId).timeout(OfflineAwareMixin.loadTimeout);
          markFresh();
          return;
        } catch (e) {
          debugPrint('Sin red para las mesas, se usa lo guardado: $e');
          if (!await _loadSaved()) rethrow;
          return;
        }
      }

      if (!await _loadSaved()) {
        _errorMessage = 'Sin conexión y aún no tenemos mesas guardadas.';
      }
    } catch (e) {
      _errorMessage = userMessage(e, network: 'No pudimos traer las mesas cercanas, intenta de nuevo');
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // The list the network answers, and which of those tables the user already joined
  Future<void> _loadFromNetwork(int userId) async {
    final all = await _openTableService.getAll();
    final now = DateTime.now();
    final tables = all
        .where((t) => t.status == OpenTableStatusEnum.OPEN && t.endTime.isAfter(now))
        .toList();

    // Save the list the network answered; it is not awaited and never breaks the screen
    SofiaLocalCache.instance.saveOpenTables(OpenTableListType.all, tables);

    final checks = await Future.wait(tables.map((t) => _isParticipant(t.id, userId)));
    final joinedIds = <int>{};
    for (int i = 0; i < tables.length; i++) {
      if (checks[i]) {
        joinedIds.add(tables[i].id);
      }
    }
    _openTables = tables;
    _joinedTableIds = joinedIds;
    _notify();
  }

  // Shows the list saved in SQLite ('ALL'); returns false if nothing is saved.
  // The tables of the user ('MINE') tell which ones were already joined.
  Future<bool> _loadSaved() async {
    try {
      final cache = SofiaLocalCache.instance;
      final saved = await cache.openTables.getAll(OpenTableListType.all);
      if (saved.isEmpty) return false;

      final mine = await cache.openTables.getAll(OpenTableListType.mine);
      final now = DateTime.now();
      _openTables = saved.where((t) => t.endTime.isAfter(now)).toList();
      _joinedTableIds = mine.map((t) => t.id).toSet();

      // "Mine" is only saved when that screen was opened; the saved details also know who was in each table
      final userId = _userId;
      if (userId != null) {
        final details = await cache.openTableDetails.getAll();
        for (final d in details) {
          if (d.participants.any((p) => p.user?.id == userId)) _joinedTableIds.add(d.table.id);
        }
      }
      markFromCache(await cache.openTables.lastSavedAt(OpenTableListType.all));
      return true;
    } catch (e) {
      debugPrint('No se pudieron leer las mesas guardadas: $e');
      return false;
    }
  }

  // Checks if the user already joined a table - GET /open-table-participants/table/{tableId}
  Future<bool> _isParticipant(int tableId, int userId) async {
    try {
      final List<OpenTableParticipant> list = await _participantService.getByOpenTable(tableId).timeout(OfflineAwareMixin.loadTimeout);
      return list.any((p) => p.user?.id == userId);
    } catch (_) {
      return false;
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
