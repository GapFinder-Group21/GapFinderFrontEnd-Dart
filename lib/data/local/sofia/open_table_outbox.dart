import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/local_file_store.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/core/utils/date_formatter_util.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';
import 'package:gapfinderfrontend_dart/services/open_table_service.dart';

// Eventual connectivity for open tables: join, leave and create work offline.
// The action is saved in the SQLite outbox (gapfinder.db) and sent when the internet comes back.
// Creating a table is multipart (data + photo), so it has its own handler here.
class OpenTableOutbox {
  static const joinType = 'open_table_join';
  static const leaveType = 'open_table_leave';
  static const createType = 'open_table_create';

  // Copies of the photos of queued tables (the camera temp folder can be cleaned by the OS)
  static const photosFolder = 'outbox_photos';

  // Max wait when the activity has no known duration
  static const defaultMaxWait = Duration(hours: 1);

  // Uploading the photo can be slow right after the network comes back
  static const uploadTimeout = Duration(seconds: 60);

  static const expiredMessage = 'La mesa esperó demasiado sin conexión y su hueco ya pasó, así que no se publicó';
  static const photoMissingMessage = 'La foto de la mesa ya no está en el celular, así que no se publicó';

  // The user id is part of the keys: an action is never sent with another user's token
  static String joinKey(int? userId, int tableId) => 'open_table_join:${userId ?? ''}:$tableId';
  static String leaveKey(int? userId, int tableId) => 'open_table_leave:${userId ?? ''}:$tableId';
  // One key per form: many taps on Publish leave a single queued table
  static String createKey(int userId, DateTime openedAt) =>
      'open_table_create:$userId:${openedAt.millisecondsSinceEpoch}';

  // Name of a new table for the user, e.g. "Café en ML"
  static String createLabel(String title, String buildingName) => '$title en $buildingName';

  // Relative path -> full path (replaced in tests)
  @visibleForTesting
  static Future<String> Function(String relative) resolvePath = LocalFileStore.instance.absolutePath;

  // EVENTUAL CONNECTIVITY JOEL: SQLite queue + local file (create an Open Table offline)
  // Queues a new table with a copy of its photo. Returns false if the same form was already queued.
  static Future<bool> enqueueCreate({
    required int userId,
    required int buildingId,
    required String buildingName,
    required OpenTable table,
    required int durationMinutes,
    required File photo,
    required DateTime openedAt,
    OutboxService? outbox,
    OpenTableService? service,
  }) async {
    final relative = '$photosFolder/${userId}_${openedAt.millisecondsSinceEpoch}.jpg';
    final copy = File(await resolvePath(relative));
    await copy.parent.create(recursive: true);
    await photo.copy(copy.path);

    final payload = (service ?? OpenTableService()).createPayload(table, userId, buildingId);
    return (outbox ?? OutboxService.instance).enqueue(
      type: createType,
      method: 'POST',
      endpoint: '/open-tables',
      body: {
        'creatorId': userId,
        'buildingId': buildingId,
        'table': payload,
        'durationMinutes': durationMinutes,
        'queuedAt': DateTime.now().toIso8601String(),
        'photo': relative,
      },
      dedupeKey: createKey(userId, openedAt),
      label: createLabel(table.title, buildingName),
    );
  }

  // Connects the create handler to the outbox (called from registerOutboxHandlers)
  static void register({OutboxService? outbox, OpenTableService? service, DateTime Function()? now}) {
    final box = outbox ?? OutboxService.instance;
    box.registerHandler(
      createType,
      (row) => _sendCreate(row, box, service ?? OpenTableService(), now ?? DateTime.now),
    );
  }

  // Returns true when the row can leave the outbox (published or refused for good)
  static Future<bool> _sendCreate(
    Map<String, dynamic> row,
    OutboxService outbox,
    OpenTableService service,
    DateTime Function() now,
  ) async {
    final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
    final photoPath = body['photo'] as String;
    final duration = (body['durationMinutes'] as num?)?.toInt() ?? 0;
    final queuedAt = DateTime.tryParse(body['queuedAt'] as String? ?? '') ?? now();
    final current = now();

    // The table was for that free gap: too late to publish it
    final maxWait = duration > 0 ? Duration(minutes: duration) : defaultMaxWait;
    if (current.difference(queuedAt) > maxWait) {
      await outbox.recordRefusal(row, expiredMessage);
      await _deletePhoto(photoPath);
      return true;
    }

    final photo = File(await resolvePath(photoPath));
    if (!await photo.exists()) {
      await outbox.recordRefusal(row, photoMissingMessage);
      return true;
    }

    // A send that timed out may still have been saved by the back: never create it twice
    if (await _alreadyCreated(body, queuedAt, service)) {
      await _deletePhoto(photoPath);
      return true;
    }

    // Times are set when it is sent: the back needs endTime in the future
    final payload = Map<String, dynamic>.from(body['table'] as Map);
    payload['startTime'] = DateFormatterUtil.formatDateTime(current);
    payload['endTime'] = DateFormatterUtil.formatDateTime(current.add(Duration(minutes: duration)));

    final res = await service.postCreate(payload, photo).timeout(uploadTimeout);
    if (res.statusCode == 201 || res.statusCode == 200) {
      await _deletePhoto(photoPath);
      return true;
    }
    if (OutboxService.isFinalRefusal(res.statusCode)) {
      await outbox.recordRefusal(row, service.createRefusalMessage(res));
      await _deletePhoto(photoPath);
      return true;
    }
    throw Exception('HTTP ${res.statusCode}');
  }

  // True if the back already has this table (same creator, building, title and description,
  // started after it was queued). Covers a send whose answer was lost.
  static Future<bool> _alreadyCreated(Map<String, dynamic> body, DateTime queuedAt, OpenTableService service) async {
    final table = body['table'] as Map;
    final creatorId = (body['creatorId'] as num).toInt();
    final buildingId = (body['buildingId'] as num).toInt();
    // Small margin: an online try that failed starts a moment before it is queued
    final since = queuedAt.subtract(const Duration(minutes: 5));

    final all = await service.getAll().timeout(OutboxService.sendTimeout);
    return all.any((t) =>
        t.creator?.id == creatorId &&
        t.building?.id == buildingId &&
        t.title == table['title'] &&
        t.description == table['description'] &&
        !t.startTime.isBefore(since));
  }

  static Future<void> _deletePhoto(String relative) async {
    try {
      final file = File(await resolvePath(relative));
      if (await file.exists()) await file.delete();
    } catch (e) {
      debugPrint('Could not delete the queued photo: $e');
    }
  }
}
