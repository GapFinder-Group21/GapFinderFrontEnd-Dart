import 'package:gapfinderfrontend_dart/core/storage/database_module.dart';

// Tables of the onboarding (interests) and of the match candidates that were shown.
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
  ],
);
