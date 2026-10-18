import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/models/enums/open_table_status_enum.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/services/location_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_participant_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';

// State and logic of the open tables tab
class OpenTablesViewModel extends ChangeNotifier {
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

  // Load the tables and reload them when the GPS is turned on or off
  Future<void> init() async {
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

  // Load the open tables that are still open - GET /open-tables
  Future<void> refresh() async {
    _isLoading = true;
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

      final all = await _openTableService.getAll();
      final now = DateTime.now();
      _openTables = all
          .where((t) => t.status == OpenTableStatusEnum.OPEN && t.endTime.isAfter(now))
          .toList();

      final checks = await Future.wait(_openTables.map((t) => _isParticipant(t.id, userId)));
      final joinedIds = <int>{};
      for (int i = 0; i < _openTables.length; i++) {
        if (checks[i]) {
          joinedIds.add(_openTables[i].id);
        }
      }
      _joinedTableIds = joinedIds;
      _notify();
    } catch (e) {
      _errorMessage = e.toString().replaceAll('Exception: ', '');
      _notify();
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // Checks if the user already joined a table - GET /open-table-participants/table/{tableId}
  Future<bool> _isParticipant(int tableId, int userId) async {
    try {
      final List<OpenTableParticipant> list = await _participantService.getByOpenTable(tableId);
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
