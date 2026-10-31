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

// What the back answered when it refused an action for good (full table, ended, match time passed...).
// It is saved so the screen that queued the action can tell the user why it did not happen, even if
// nobody was looking when it was sent.
const outboxRefusalsModule = DatabaseModule(
  name: 'outbox_refusals',
  createStatements: [
    '''
    CREATE TABLE IF NOT EXISTS outbox_refusals (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      key TEXT NOT NULL,
      type TEXT NOT NULL,
      message TEXT NOT NULL,
      created_at TEXT NOT NULL
    )
    ''',
    'CREATE INDEX IF NOT EXISTS idx_outbox_refusals_key ON outbox_refusals(key)',
  ],
);

// An action that the back refused for good
class OutboxRefusal {
  final String key;
  final String type;
  final String message;
  final DateTime createdAt;

  const OutboxRefusal({required this.key, required this.type, required this.message, required this.createdAt});
}

// Sends one request to the back (replaced in tests)
typedef OutboxSender = Future<http.Response> Function(String method, String endpoint, Map<String, dynamic>? body);

// Actions done without connection, saved to be sent later, in the same order they were made
class OutboxService {
  // After this many failed tries a row is not retried anymore
  static const maxAttempts = 5;

  // A request that takes longer than this counts as a network failure (nothing is lost, it is retried)
  static const sendTimeout = Duration(seconds: 15);

  // After a network failure the rest of the rows is tried again after this time
  static const retryDelay = Duration(seconds: 15);

  static final OutboxService instance = OutboxService._(
    database: () => AppDatabase.instance.database,
    send: _sendWithApiClient,
    isOnline: () => ConnectivityService.instance.checkNow(),
  );

  OutboxService._({
    required this._database,
    required this._send,
    required this._isOnline,
  })  : _flushOnEnqueue = true,
        _sendTimeout = sendTimeout,
        _retryDelay = retryDelay;

  @visibleForTesting
  OutboxService.forTesting({
    required this._database,
    required this._send,
    Future<bool> Function()? isOnline,
    this._flushOnEnqueue = false,
    this._sendTimeout = OutboxService.sendTimeout,
    this._retryDelay,
  }) : _isOnline = isOnline ?? (() async => true);

  final Future<Database> Function() _database;
  final OutboxSender _send;
  final Future<bool> Function() _isOnline;
  // The real app tries to send right after saving; tests turn it off to read the table as it was saved
  final bool _flushOnEnqueue;
  final Duration _sendTimeout;
  // null = never retry by itself (tests)
  final Duration? _retryDelay;

  // A 4xx answer means the back refused the action for good (full table, ended...), so retrying
  // is useless. These ones are the exception: they can pass later.
  static const _retryableClientErrors = {401, 403, 408, 429};

  final Map<String, Future<bool> Function(Map<String, dynamic> row)> _handlers = {};
  final _changes = StreamController<void>.broadcast();
  final _refusals = StreamController<OutboxRefusal>.broadcast();
  StreamSubscription<bool>? _connectivitySub;
  Timer? _retryTimer;
  bool _initialized = false;
  bool _flushing = false;
  // Something was saved while a flush was running: that flush already read its rows, so it must run again
  bool _flushAgain = false;

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
      // A new action with the same key: the old refusal of that key is no longer valid
      if (dedupeKey != null) {
        await db.delete('outbox_refusals', where: 'key = ?', whereArgs: [dedupeKey]);
      }
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

  // The body of the action waiting with this key (null if there is none or it has no body)
  Future<String?> pendingBody(String dedupeKey) async {
    final db = await _database();
    final rows = await db.query('outbox', columns: ['body'], where: 'dedupe_key = ?', whereArgs: [dedupeKey], limit: 1);
    return rows.isEmpty ? null : rows.first['body'] as String?;
  }

  // True if the row still has the body it had when it was read (false if it was replaced or cancelled).
  // A handler asks it before it writes anything that depends on what it sent.
  Future<bool> hasSameBody(Map<String, dynamic> row) async {
    final db = await _database();
    final rows = await db.query('outbox', columns: ['body'], where: 'id = ?', whereArgs: [row['id']], limit: 1);
    return rows.isNotEmpty && rows.first['body'] == row['body'];
  }

  // Removes a pending action (for example "join" when the user taps "leave" before it was sent)
  Future<void> cancelPending(String dedupeKey) async {
    final db = await _database();
    await db.delete('outbox', where: 'dedupe_key = ?', whereArgs: [dedupeKey]);
    _changes.add(null);
  }

  // Removes every pending action and every saved refusal (used when the session ends: the actions
  // of one user must never be sent with the token of the next one)
  Future<void> clearAll() async {
    _retryTimer?.cancel();
    final db = await _database();
    await db.delete('outbox');
    await db.delete('outbox_refusals');
    _changes.add(null);
  }

  // Actions that the back refused for good, as they happen
  Stream<OutboxRefusal> get refusals => _refusals.stream;

  // The last refusal of the action with this key (null if there is none)
  Future<OutboxRefusal?> lastRefusalFor(String key) async {
    final db = await _database();
    final rows = await db.query('outbox_refusals', where: 'key = ?', whereArgs: [key], orderBy: 'id DESC', limit: 1);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return OutboxRefusal(
      key: row['key'] as String,
      type: row['type'] as String,
      message: row['message'] as String,
      createdAt: DateTime.tryParse(row['created_at'] as String) ?? DateTime.now(),
    );
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

  // Sends the pending actions in the order they were made. Two flushes never run at the same time, but if
  // something was saved while one was running, it runs again when it finishes (so nothing waits for an event
  // that may never come).
  // A row is deleted when it works or when the back answers 409 (the action was already done).
  // A 422 or another final 4xx means the back refused it: the row is deleted and the refusal is saved.
  // If it fails, attempts grows and the error is saved; after maxAttempts it is not retried.
  Future<void> flush() async {
    if (_flushing) {
      _flushAgain = true;
      return;
    }
    _flushing = true;

    try {
      do {
        _flushAgain = false;

        // Without connection nothing is sent, so the attempts are not wasted
        if (!await _isOnline()) break;

        final db = await _database();
        final rows = await db.query('outbox', where: 'attempts < ?', whereArgs: [maxAttempts], orderBy: 'id ASC');

        for (final row in rows) {
          final keepGoing = await _sendRow(db, Map<String, dynamic>.from(row));
          _changes.add(null);
          if (!keepGoing) {
            // The network failed: the rest waits without using attempts and is tried again later
            _scheduleRetry();
            break;
          }
        }
      } while (_flushAgain);
    } catch (e) {
      debugPrint('Error sending the outbox: $e');
    } finally {
      _flushing = false;
    }
  }

  // After a network failure the platform may still say "online", so no event would ever call flush
  // again: it tries again by itself after a while
  void _scheduleRetry() {
    final delay = _retryDelay;
    if (delay == null || _retryTimer?.isActive == true) return;
    _retryTimer = Timer(delay, flush);
  }

  // Returns false when the network failed, so flush stops and no attempt is wasted on the rest
  Future<bool> _sendRow(Database db, Map<String, dynamic> queued) async {
    final id = queued['id'] as int;

    try {
      // The row is read again: the user may have cancelled it, or replaced its body, while the rows
      // before it were being sent
      final current = await db.query('outbox', where: 'id = ?', whereArgs: [id], limit: 1);
      if (current.isEmpty) return true;
      final row = Map<String, dynamic>.from(current.first);

      final handler = _handlers[row['type']];
      if (handler != null) {
        if (!await handler(row)) throw Exception('The handler could not do the action');
      } else {
        final body = row['body'] == null ? null : jsonDecode(row['body'] as String) as Map<String, dynamic>;
        final res = await _send(row['method'] as String, row['endpoint'] as String, body).timeout(_sendTimeout);

        // 409: the back says the action was already done, so it is not an error
        final done = (res.statusCode >= 200 && res.statusCode < 300) || res.statusCode == 409;
        if (!done) {
          final refusedForGood =
              res.statusCode >= 400 && res.statusCode < 500 && !_retryableClientErrors.contains(res.statusCode);
          if (refusedForGood) {
            // The row is removed and the refusal is saved: whoever was waiting for the key to leave
            // can tell the user why the action did not happen
            debugPrint('Outbox: the back refused ${row['type']} (HTTP ${res.statusCode}), it is dropped');
            await db.delete('outbox', where: 'id = ?', whereArgs: [id]);
            await _saveRefusal(db, row, res);
            return true;
          }
          throw Exception('HTTP ${res.statusCode}');
        }
      }

      // Only if the body is still the one that was sent: if the user replaced it while it was being sent
      // (replaceIfPending), the row stays with the newer body and the next flush sends it
      await db.delete('outbox', where: 'id = ? AND body IS ?', whereArgs: [id, row['body']]);
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

  // Saves the refusal of the back and tells whoever is listening
  Future<void> _saveRefusal(Database db, Map<String, dynamic> row, http.Response res) async {
    final refusal = OutboxRefusal(
      key: (row['dedupe_key'] as String?) ?? '',
      type: row['type'] as String,
      message: _refusalMessage(res),
      createdAt: DateTime.now(),
    );

    try {
      await db.insert('outbox_refusals', {
        'key': refusal.key,
        'type': refusal.type,
        'message': refusal.message,
        'created_at': refusal.createdAt.toIso8601String(),
      });
    } catch (e) {
      debugPrint('Outbox: the refusal could not be saved: $e');
    }
    if (!_refusals.isClosed) _refusals.add(refusal);
  }

  // The text of the back in Spanish when it is readable, otherwise a message of our own
  static String _refusalMessage(http.Response res) {
    const fallback = 'El servidor no aceptó la acción';
    final body = utf8.decode(res.bodyBytes, allowMalformed: true).trim();
    if (body.isEmpty) return fallback;

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final text = (decoded['error'] ?? decoded['message'])?.toString() ?? '';
        return plainBackendText(text, fallback);
      }
      if (decoded is String) return plainBackendText(decoded, fallback);
    } catch (_) {
      // Not JSON: plain text
    }
    return plainBackendText(body, fallback);
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
    _retryTimer?.cancel();
    await _connectivitySub?.cancel();
    await _changes.close();
    await _refusals.close();
  }
}
