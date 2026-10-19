import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_cache_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/services/open_table_participant_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// Open tables the user created and the ones they joined
class MyOpenTablesViewModel extends ChangeNotifier with OfflineAwareMixin {
  final OpenTableService _openTableService;
  final OpenTableParticipantService _participantService;

  MyOpenTablesViewModel({
    OpenTableService? openTableService,
    OpenTableParticipantService? participantService,
  })  : _openTableService = openTableService ?? OpenTableService(),
        _participantService = participantService ?? OpenTableParticipantService();

  List<OpenTable> _createdTables = [];
  List<OpenTable> _joinedTables = [];
  bool _isLoading = true;
  String? _error;
  bool _disposed = false;

  List<OpenTable> get createdTables => _createdTables;
  List<OpenTable> get joinedTables => _joinedTables;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isEmpty => _createdTables.isEmpty && _joinedTables.isEmpty;

  // Load the tables when the screen opens; reload by itself when the connection comes back
  Future<void> init() {
    listenToConnectivity(onRestored: refresh);
    return refresh();
  }

  // Network falling back to cache: loads the tables created and joined by the user - GET /open-tables.
  // Without connection (or if the call fails or is too slow) it shows the 'MINE' list saved in SQLite.
  Future<void> refresh() async {
    _isLoading = isEmpty;
    _error = null;
    _notify();
    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return;

      if (hasConnection) {
        try {
          await _loadFromNetwork(userId).timeout(OfflineAwareMixin.loadTimeout);
          markFresh();
          return;
        } catch (e) {
          debugPrint('Sin red para mis mesas, se usa lo guardado: $e');
          if (!await _loadSaved(userId)) rethrow;
          return;
        }
      }

      if (!await _loadSaved(userId)) {
        _error = 'Sin conexión y aún no tienes mesas guardadas.';
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> _loadFromNetwork(int userId) async {
    final all = await _openTableService.getAll();
    final created = all.where((t) => t.creator?.id == userId).toList();
    final others = all.where((t) => t.creator?.id != userId).toList();

    final joined = <OpenTable>[];
    final checks = await Future.wait(others.map((t) => _isParticipant(t.id, userId)));
    for (var i = 0; i < others.length; i++) {
      if (checks[i]) joined.add(others[i]);
    }

    _createdTables = created;
    _joinedTables = joined;

    // Save my tables (created + joined); it is not awaited and never breaks the screen
    SofiaLocalCache.instance.saveOpenTables(OpenTableListType.mine, [...created, ...joined]);
  }

  // Shows the 'MINE' list saved in SQLite; returns false if nothing is saved
  Future<bool> _loadSaved(int userId) async {
    try {
      final cache = SofiaLocalCache.instance;
      final saved = await cache.openTables.getAll(OpenTableListType.mine);
      if (saved.isEmpty) return false;

      _createdTables = saved.where((t) => t.creator?.id == userId).toList();
      _joinedTables = saved.where((t) => t.creator?.id != userId).toList();
      markFromCache(await cache.openTables.lastSavedAt(OpenTableListType.mine));
      return true;
    } catch (e) {
      debugPrint('No se pudieron leer mis mesas guardadas: $e');
      return false;
    }
  }

  // Check if the user is a participant - GET /open-table-participants/table/{tableId}
  Future<bool> _isParticipant(int tableId, int userId) async {
    final List<OpenTableParticipant> list = await _participantService.getByOpenTable(tableId).timeout(OfflineAwareMixin.loadTimeout);
    return list.any((p) => p.user?.id == userId);
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
