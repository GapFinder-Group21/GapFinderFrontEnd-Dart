import 'package:gapfinderfrontend_dart/core/storage/database_module.dart';

// Tables of Sofia's data: the schedule (classes and gaps) and the open tables.
// Each row keeps saved_at so the app can say "updated at HH:mm".
const sofiaDatabaseModule = DatabaseModule(
  name: 'sofia',
  createStatements: [
    '''
    CREATE TABLE IF NOT EXISTS class_blocks (
      id INTEGER PRIMARY KEY,
      user_id INTEGER,
      subject TEXT,
      location TEXT,
      day_of_week TEXT,
      start_time TEXT,
      end_time TEXT,
      saved_at TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS gaps (
      id INTEGER PRIMARY KEY,
      user_id INTEGER,
      start_time TEXT,
      end_time TEXT,
      saved_at TEXT
    )
    ''',
    // list_type: 'ALL' (open_tables_view) or 'MINE' (my_open_tables_view).
    // The key is (id, list_type) so a table that is in both lists is saved once in each one.
    '''
    CREATE TABLE IF NOT EXISTS open_tables_cache (
      id INTEGER NOT NULL,
      json TEXT,
      list_type TEXT NOT NULL,
      saved_at TEXT,
      PRIMARY KEY (id, list_type)
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS open_table_details (
      id INTEGER PRIMARY KEY,
      json TEXT,
      participants_json TEXT,
      saved_at TEXT
    )
    ''',
  ],
);
