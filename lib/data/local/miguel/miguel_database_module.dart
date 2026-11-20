import 'package:gapfinderfrontend_dart/core/storage/database_module.dart';

// STORAGE MIGUEL: SQLite (interests catalog, user interests, seen candidates and study periods)
// Tables of the onboarding (interests), of the match candidates that were shown and of the study mode.
// The catalog and the candidates keep the whole object as JSON; user_interests is a plain relation
// between a user and an interest, with synced = 1 when the back already received it.
const miguelDatabaseModule = DatabaseModule(
  name: 'miguel',
  createStatements: [
    """
    CREATE TABLE IF NOT EXISTS interests_catalog (
      id INTEGER PRIMARY KEY,
      name TEXT,
      json TEXT,
      saved_at TEXT
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS user_interests (
      user_id INTEGER,
      interest_id INTEGER,
      synced INTEGER,
      PRIMARY KEY (user_id, interest_id)
    )
    """,
    """
    CREATE TABLE IF NOT EXISTS seen_candidates (
      match_id INTEGER PRIMARY KEY,
      json TEXT,
      saved_at TEXT
    )
    """,
    // Estrategia: Local storage (SQLite). The study periods of each user. client_id is the id made on the
    // phone, so a period exists before the back knows it (server_id is null and synced = 0 until it does).
    // start_time and end_time are ISO text in local time; gap_id is only informational.
    """
    CREATE TABLE IF NOT EXISTS study_periods (
      client_id TEXT PRIMARY KEY,
      server_id INTEGER,
      user_id INTEGER NOT NULL,
      gap_id INTEGER,
      start_time TEXT NOT NULL,
      end_time TEXT NOT NULL,
      synced INTEGER NOT NULL DEFAULT 0
    )
    """,
    'CREATE INDEX IF NOT EXISTS idx_study_periods_user ON study_periods(user_id, end_time)',
  ],
);
