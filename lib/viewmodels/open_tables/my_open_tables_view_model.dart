import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/open_table_cache_dao.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
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

  // Network falling back to cache: loads the tables created and joined by the user - GET /open-tables and
  // GET /open-table-participants/user/{userId}.
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
      _error = userMessage(e, network: 'No pudimos traer tus mesas, revisa tu conexión e intenta de nuevo');
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // Two requests, at the same time: all the tables (the ones the user created are found by their creator)
  // and the tables the user joined. Never one request per table.
  Future<void> _loadFromNetwork(int userId) async {
    final results = await Future.wait([
      _openTableService.getAll(),
      _participantService.getJoinedOpenTables(userId),
    ]);
    final all = results[0];
    final created = all.where((t) => t.creator?.id == userId).toList();
    final joined = results[1].where((t) => t.creator?.id != userId).toList();

    _createdTables = created;
    _joinedTables = joined;

    // Save my tables (created + joined) and whose they are; it is not awaited and never breaks the screen
    SofiaLocalCache.instance.saveOpenTables(OpenTableListType.mine, [...created, ...joined], userId: userId);
    SofiaLocalCache.instance.saveMyTablesOwner(userId);
  }

  // Shows the 'MINE' list saved in SQLite; returns false if nothing is saved
  Future<bool> _loadSaved(int userId) async {
    try {
      final cache = SofiaLocalCache.instance;
      // The saved list belongs to one user: another user (for example after the session expired) never sees it
      final owner = await cache.myTablesOwner();
      if (owner != null && owner != userId) return false;
      final saved = await cache.openTables.getAll(OpenTableListType.mine);
      // A user with no tables saved an empty list: that is an answer, not "never saved"
      final savedAt = await cache.savedAt(OpenTableListType.mine, userId) ?? await cache.openTables.lastSavedAt(OpenTableListType.mine);
      if (saved.isEmpty && savedAt == null) return false;

      _createdTables = saved.where((t) => t.creator?.id == userId).toList();
      _joinedTables = saved.where((t) => t.creator?.id != userId).toList();
      markFromCache(savedAt);
      return true;
    } catch (e) {
      debugPrint('No se pudieron leer mis mesas guardadas: $e');
      return false;
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
