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
    // Estrategia: Local storage (SQLite). History of "Mis matches", one row per match of each user.
    // The key is (id, user_id): the same match is seen by its two students, each with their own rating.
    '''
    CREATE TABLE IF NOT EXISTS match_history (
      id INTEGER NOT NULL,
      user_id INTEGER NOT NULL,
      json TEXT,
      saved_at TEXT,
      PRIMARY KEY (id, user_id)
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_match_history_user ON match_history(user_id)',
  ],
);
