import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';

// Catalog of interests of the back (table interests_catalog)
class InterestsCatalogDao {
  final Future<Database> Function() _database;

  InterestsCatalogDao({Future<Database> Function()? database})
      : _database = database ?? (() => AppDatabase.instance.database);

  // Replaces the whole catalog with the last network answer, in one batch
  Future<void> replaceAll(List<Interest> interests) async {
    final savedAt = DateTime.now().toIso8601String();
    final db = await _database();

    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete('interests_catalog');
      for (final interest in interests) {
        batch.insert(
          'interests_catalog',
          {
            'id': interest.id,
            'name': interest.name,
            'json': jsonEncode(interest.toJson()),
            'saved_at': savedAt,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await batch.commit(noResult: true);
    });
  }

  Future<List<Interest>> getAll() async {
    final db = await _database();
    final rows = await db.query('interests_catalog', orderBy: 'id ASC');
    return rows.map((r) => Interest.fromJson(jsonDecode(r['json'] as String) as Map<String, dynamic>)).toList();
  }

  // When the catalog was last saved, or null if there is none
  Future<DateTime?> lastSavedAt() async {
    final db = await _database();
    final rows = await db.rawQuery('SELECT MAX(saved_at) AS last FROM interests_catalog');
    final last = rows.first['last'] as String?;
    return last == null ? null : DateTime.parse(last);
  }
}
