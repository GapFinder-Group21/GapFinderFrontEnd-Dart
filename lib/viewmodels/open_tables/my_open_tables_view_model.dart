import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';
import 'package:gapfinderfrontend_dart/services/open_table_participant_service.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';

// Open tables the user created and the ones they joined
class MyOpenTablesViewModel extends ChangeNotifier {
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

  // Load the tables when the screen opens
  Future<void> init() => refresh();

  // Load the tables created and joined by the user - GET /open-tables
  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    _notify();
    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) return;

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
      _isLoading = false;
      _notify();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      _notify();
    }
  }

  // Check if the user is a participant - GET /open-table-participants/table/{tableId}
  Future<bool> _isParticipant(int tableId, int userId) async {
    final List<OpenTableParticipant> list = await _participantService.getByOpenTable(tableId);
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
