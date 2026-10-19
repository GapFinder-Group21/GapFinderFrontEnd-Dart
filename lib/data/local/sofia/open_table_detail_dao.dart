import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/models/open_table_participant.dart';

// A saved detail: the table and its participants
class OpenTableDetailRecord {
  final OpenTable table;
  final List<OpenTableParticipant> participants;
  final DateTime? savedAt;
  OpenTableDetailRecord(this.table, this.participants, this.savedAt);
}

// Table open_table_details: the detail screen of each table the user opened
class OpenTableDetailDao {
  static const table = 'open_table_details';

  final Future<Database> Function() _database;

  OpenTableDetailDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Saves (or replaces) the detail of one table
  Future<void> save(OpenTable openTable, List<OpenTableParticipant> participants) async {
    final db = await _database();
    await db.insert(
      table,
      _toRow(openTable, participants, DateTime.now().toIso8601String()),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Replaces all the saved details in one transaction
  Future<void> replaceAll(List<MapEntry<OpenTable, List<OpenTableParticipant>>> details) async {
    final db = await _database();
    final savedAt = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete(table);
      for (final d in details) {
        batch.insert(table, _toRow(d.key, d.value, savedAt), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<OpenTableDetailRecord>> getAll() async {
    final db = await _database();
    final rows = await db.query(table, orderBy: 'id');
    return rows.map(_fromRow).toList();
  }

  Future<OpenTableDetailRecord?> getById(int id) async {
    final db = await _database();
    final rows = await db.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  // When the detail of this table was saved, or null if it was never saved
  Future<DateTime?> lastSavedAt(int id) async {
    final db = await _database();
    final rows = await db.query(table, columns: ['saved_at'], where: 'id = ?', whereArgs: [id], limit: 1);
    if (rows.isEmpty) return null;
    return DateTime.tryParse(rows.first['saved_at'] as String? ?? '');
  }

  Map<String, Object?> _toRow(OpenTable openTable, List<OpenTableParticipant> participants, String savedAt) {
    return {
      'id': openTable.id,
      'json': jsonEncode(openTable.toCacheJson()),
      'participants_json': jsonEncode(participants.map((p) => p.toCacheJson()).toList()),
      'saved_at': savedAt,
    };
  }

  OpenTableDetailRecord _fromRow(Map<String, Object?> row) {
    final participants = (jsonDecode(row['participants_json'] as String? ?? '[]') as List)
        .map((p) => OpenTableParticipant.fromJson(p as Map<String, dynamic>))
        .toList();
    return OpenTableDetailRecord(
      OpenTable.fromJson(jsonDecode(row['json'] as String) as Map<String, dynamic>),
      participants,
      DateTime.tryParse(row['saved_at'] as String? ?? ''),
    );
  }
}
