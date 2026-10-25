import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/app_database.dart';
import 'package:gapfinderfrontend_dart/core/storage/database_module.dart';

// Table of the actions waiting to be sent to the back.
// The unique index lets the database itself refuse two equal pending actions: if the user taps
// "join" nine times without connection, only one row exists, so when the network comes back the
// action is sent once, not nine times.
const outboxModule = DatabaseModule(
  name: 'outbox',
  createStatements: [
    '''
    CREATE TABLE IF NOT EXISTS outbox (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      type TEXT NOT NULL,
      method TEXT NOT NULL,
      endpoint TEXT NOT NULL,
      body TEXT,
      dedupe_key TEXT,
      created_at TEXT NOT NULL,
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT
    )
    ''',
    'CREATE UNIQUE INDEX IF NOT EXISTS idx_outbox_dedupe ON outbox(dedupe_key) WHERE dedupe_key IS NOT NULL',
  ],
);

// Sends one request to the back (replaced in tests)
typedef OutboxSender = Future<http.Response> Function(String method, String endpoint, Map<String, dynamic>? body);

// Actions done without connection, saved to be sent later, in the same order they were made
class OutboxService {
  // After this many failed tries a row is not retried anymore
  static const maxAttempts = 5;

  static final OutboxService instance = OutboxService._(
    database: () => AppDatabase.instance.database,
    send: _sendWithApiClient,
    isOnline: () => ConnectivityService.instance.checkNow(),
  );

  OutboxService._({
    required this._database,
    required this._send,
    required this._isOnline,
  }) : _flushOnEnqueue = true;

  @visibleForTesting
  OutboxService.forTesting({
    required this._database,
    required this._send,
    Future<bool> Function()? isOnline,
    this._flushOnEnqueue = false,
  }) : _isOnline = isOnline ?? (() async => true);

  final Future<Database> Function() _database;
  final OutboxSender _send;
  final Future<bool> Function() _isOnline;
  // The real app tries to send right after saving; tests turn it off to read the table as it was saved
  final bool _flushOnEnqueue;

  // A 4xx answer means the back refused the action for good (full table, ended...), so retrying
  // is useless. These ones are the exception: they can pass later.
  static const _retryableClientErrors = {401, 403, 408, 429};

  final Map<String, Future<bool> Function(Map<String, dynamic> row)> _handlers = {};
  final _changes = StreamController<void>.broadcast();
  StreamSubscription<bool>? _connectivitySub;
  bool _initialized = false;
  bool _flushing = false;

  // Sends the pending actions at start and every time the connection comes back
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    _connectivitySub = ConnectivityService.instance.onStatusChange.listen((online) {
      if (online) flush();
    });
    flush(); // not awaited: the app must not wait for the network
  }

  // For actions that are not a simple JSON request (for example uploading a photo).
  // The handler receives the row and returns true when the action was done.
  void registerHandler(String type, Future<bool> Function(Map<String, dynamic> row) handler) {
    _handlers[type] = handler;
  }

  // Saves an action to send it later.
  // With a dedupeKey only one pending action with that key can exist: returns false if there is
  // already one (it is not duplicated), unless replaceIfPending is true, which replaces its body.
  // A row that already used all its attempts does not count as pending and is replaced.
  Future<bool> enqueue({
    required String type,
    required String method,
    required String endpoint,
    Map<String, dynamic>? body,
    String? dedupeKey,
    bool replaceIfPending = false,
  }) async {
    final db = await _database();
    final encodedBody = body == null ? null : jsonEncode(body);

    final saved = await db.transaction<bool>((txn) async {
      if (dedupeKey != null) {
        final existing = await txn.query('outbox', where: 'dedupe_key = ?', whereArgs: [dedupeKey], limit: 1);

        if (existing.isNotEmpty) {
          final row = existing.first;
          final exhausted = (row['attempts'] as int) >= maxAttempts;

          if (exhausted) {
            await txn.update(
              'outbox',
              {
                'type': type,
                'method': method,
                'endpoint': endpoint,
                'body': encodedBody,
                'created_at': DateTime.now().toIso8601String(),
                'attempts': 0,
                'last_error': null,
              },
              where: 'id = ?',
              whereArgs: [row['id']],
            );
            return true;
          }

          if (!replaceIfPending) return false;

          await txn.update('outbox', {'body': encodedBody}, where: 'id = ?', whereArgs: [row['id']]);
          return true;
        }
      }

      await txn.insert('outbox', {
        'type': type,
        'method': method,
        'endpoint': endpoint,
        'body': encodedBody,
        'dedupe_key': dedupeKey,
        'created_at': DateTime.now().toIso8601String(),
        'attempts': 0,
      });
      return true;
    });

    if (saved) {
      _changes.add(null);
      // With connection it leaves at once; without it, flush checks the real state of the network
      // (this is what notices that the wifi came back when the platform did not warn)
      if (_flushOnEnqueue) flush();
    }
    return saved;
  }

  // True if an action with this key is waiting to be sent
  Future<bool> isPending(String dedupeKey) async {
    final db = await _database();
    final rows = await db.query(
      'outbox',
      columns: ['id'],
      where: 'dedupe_key = ? AND attempts < ?',
      whereArgs: [dedupeKey, maxAttempts],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  // Removes a pending action (for example "join" when the user taps "leave" before it was sent)
  Future<void> cancelPending(String dedupeKey) async {
    final db = await _database();
    await db.delete('outbox', where: 'dedupe_key = ?', whereArgs: [dedupeKey]);
    _changes.add(null);
  }

  // The keys of the pending actions, to disable the button and show "Pendiente de enviar"
  Stream<Set<String>> get pendingKeys => _watch<Set<String>>(() async {
        final db = await _database();
        final rows = await db.query(
          'outbox',
          columns: ['dedupe_key'],
          where: 'dedupe_key IS NOT NULL AND attempts < ?',
          whereArgs: [maxAttempts],
        );
        return rows.map((r) => r['dedupe_key'] as String).toSet();
      });

  // How many actions are waiting to be sent
  Stream<int> get pendingCount => _watch<int>(() async {
        final db = await _database();
        final rows = await db.rawQuery('SELECT COUNT(*) AS total FROM outbox WHERE attempts < ?', [maxAttempts]);
        return Sqflite.firstIntValue(rows) ?? 0;
      }).distinct();

  // Sends the pending actions in the order they were made. Two flushes never run at the same time.
  // A row is deleted when it works or when the back answers 409 (the action was already done).
  // If it fails, attempts grows and the error is saved; after maxAttempts it is not retried.
  Future<void> flush() async {
    if (_flushing) return;
    _flushing = true;

    try {
      // Without connection nothing is sent, so the attempts are not wasted
      if (!await _isOnline()) return;

      final db = await _database();
      final rows = await db.query('outbox', where: 'attempts < ?', whereArgs: [maxAttempts], orderBy: 'id ASC');

      for (final row in rows) {
        final keepGoing = await _sendRow(db, Map<String, dynamic>.from(row));
        _changes.add(null);
        if (!keepGoing) break; // the network failed: the rest waits without using attempts
      }
    } catch (e) {
      debugPrint('Error sending the outbox: $e');
    } finally {
      _flushing = false;
    }
  }

  // Returns false when the network failed, so flush stops and no attempt is wasted on the rest
  Future<bool> _sendRow(Database db, Map<String, dynamic> row) async {
    final id = row['id'] as int;

    try {
      final handler = _handlers[row['type']];
      if (handler != null) {
        if (!await handler(row)) throw Exception('The handler could not do the action');
      } else {
        final body = row['body'] == null ? null : jsonDecode(row['body'] as String) as Map<String, dynamic>;
        final res = await _send(row['method'] as String, row['endpoint'] as String, body);

        // 409: the back says the action was already done, so it is not an error
        final done = (res.statusCode >= 200 && res.statusCode < 300) || res.statusCode == 409;
        if (!done) {
          final refusedForGood =
              res.statusCode >= 400 && res.statusCode < 500 && !_retryableClientErrors.contains(res.statusCode);
          if (refusedForGood) {
            // The row is removed; whoever was waiting for it sees the key leave and checks the result
            debugPrint('Outbox: the back refused ${row['type']} (HTTP ${res.statusCode}), it is dropped');
            await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
            return true;
          }
          throw Exception('HTTP ${res.statusCode}');
        }
      }

      await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
      return true;
    } catch (e) {
      if (isNetworkError(e)) return false;
      await db.rawUpdate(
        'UPDATE outbox SET attempts = attempts + 1, last_error = ? WHERE id = ?',
        [e.toString(), id],
      );
      return true;
    }
  }

  // Emits the current value when someone listens, and again every time the table changes
  Stream<T> _watch<T>(Future<T> Function() load) {
    late StreamController<T> controller;
    StreamSubscription<void>? subscription;

    Future<void> emit() async {
      try {
        final value = await load();
        if (!controller.isClosed) controller.add(value);
      } catch (e) {
        debugPrint('Error reading the outbox: $e');
      }
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  static Future<http.Response> _sendWithApiClient(String method, String endpoint, Map<String, dynamic>? body) {
    switch (method.toUpperCase()) {
      case 'POST':
        return ApiClient.post(endpoint, body: body);
      case 'PUT':
        return ApiClient.put(endpoint, body: body);
      case 'PATCH':
        return ApiClient.patch(endpoint, body: body);
      case 'DELETE':
        return ApiClient.delete(endpoint);
      case 'GET':
        return ApiClient.get(endpoint);
      default:
        throw ArgumentError('Unsupported method: $method');
    }
  }

  // Only for tests
  @visibleForTesting
  Future<void> dispose() async {
    await _connectivitySub?.cancel();
    await _changes.close();
  }
}
