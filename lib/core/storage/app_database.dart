import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/storage/database_modules.dart';

// The one SQLite database of the app (gapfinder.db). It is a singleton so that the whole app
// shares a single open connection.
class AppDatabase {
  static final AppDatabase instance = AppDatabase._();
  AppDatabase._();

  Future<Database>? _database;

  // Opens the database the first time and reuses it afterwards
  Future<Database> get database {
    return _database ??= _open().catchError((Object e) {
      _database = null; // let the next call try again
      throw e;
    });
  }

  Future<Database> _open() async {
    final path = p.join(await getDatabasesPath(), 'gapfinder.db');

    // Tables are created in onOpen with CREATE TABLE IF NOT EXISTS instead of using onCreate
    // and a version number. That way each teammate only adds a module to databaseModules and
    // never has to coordinate database versions or write migrations: new tables just appear
    // the next time the app opens. (Changing an existing table would still need a migration.)
    return openDatabase(path, onOpen: createModuleTables);
  }

  // Creates the tables of every module; public so tests can use it on an in-memory database
  @visibleForTesting
  static Future<void> createModuleTables(Database db) async {
    for (final module in databaseModules) {
      for (final statement in module.createStatements) {
        await db.execute(statement);
      }
    }
  }
}
