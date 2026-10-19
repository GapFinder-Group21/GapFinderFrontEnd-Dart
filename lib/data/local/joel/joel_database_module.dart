import 'package:gapfinderfrontend_dart/core/storage/database_module.dart';

// Tables of friends, friend requests, notifications and matches.
// Each row keeps the whole object as JSON plus the columns used to filter it.
const joelDatabaseModule = DatabaseModule(
  name: 'joel',
  createStatements: [
    '''
    CREATE TABLE IF NOT EXISTS friends (
      id INTEGER PRIMARY KEY,
      user_id INTEGER,
      json TEXT,
      saved_at TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS friend_requests (
      id INTEGER PRIMARY KEY,
      user_id INTEGER,
      json TEXT,
      saved_at TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS notifications (
      id INTEGER PRIMARY KEY,
      user_id INTEGER,
      json TEXT,
      is_read INTEGER,
      saved_at TEXT
    )
    ''',
    '''
    CREATE TABLE IF NOT EXISTS matches (
      id INTEGER PRIMARY KEY,
      user_id INTEGER,
      gap_id INTEGER,
      json TEXT,
      saved_at TEXT
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_friends_user ON friends(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_friend_requests_user ON friend_requests(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id)',
    'CREATE INDEX IF NOT EXISTS idx_matches_user ON matches(user_id)',
  ],
);
