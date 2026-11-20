import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/study_period_dao.dart';
import 'package:gapfinderfrontend_dart/models/study_period.dart';

// EVENTUAL CONNECTIVITY MIGUEL: Own SQLite queue (study mode)
// Estrategia: Eventual connectivity. Turning the study mode on or off without internet is not lost: the
// action waits in the outbox and the screen shows it at once (optimistic).
// - Turning it ON is a POST handled here (a handler of its own, like UserInterestsOutbox): after the back
//   answers, SQLite must learn the id the back gave (synced = 1), and that has to happen even if the
//   screen is closed when the internet comes back.
// - Turning it OFF a period the back already has is a plain DELETE row: nothing else has to be done.
// Both use the dedupe key study_mode:<userId>:<clientId>, so a period never has two pending actions.
class StudyModeOutbox {
  static const addType = 'study_mode_add';
  static const removeType = 'study_mode_remove';

  // What the screen tells the user when the back refused the period for good
  static const refusedMessage = 'No pudimos activar el modo estudio';

  // The user id is part of the key: an action of one user is never sent with the token of the next one
  static String key(int userId, String clientId) => 'study_mode:$userId:$clientId';

  // Prefix of every key of a user
  static String prefix(int userId) => 'study_mode:$userId:';

  // The client id of a key of this user, or null if the key is not one of theirs
  static String? clientIdOf(String key, int userId) {
    final p = prefix(userId);
    if (!key.startsWith(p) || key.length == p.length) return null;
    return key.substring(p.length);
  }

  static String endpoint(int userId) => '/users/$userId/study-mode';

  static String periodEndpoint(int userId, int serverId) => '/users/$userId/study-mode/$serverId';

  // Connects the handler to the outbox (called from registerOutboxHandlers).
  // post, get and delete are only replaced in tests.
  static void register({
    OutboxService? outbox,
    StudyPeriodDao? dao,
    Future<http.Response> Function(String path, Map<String, dynamic> body)? post,
    Future<http.Response> Function(String path)? get,
    Future<http.Response> Function(String path)? delete,
  }) {
    final service = outbox ?? OutboxService.instance;
    service.registerHandler(
      addType,
      (row) => _send(
        row,
        service,
        dao ?? StudyPeriodDao(),
        post ?? ((path, body) => ApiClient.post(path, body: body)),
        get ?? ApiClient.get,
        delete ?? ApiClient.delete,
      ),
    );
  }

  // Queues "turn on": POST /users/{userId}/study-mode {startTime, endTime, gapId, clientId}.
  // The row keeps the user id too, because the handler needs it and the body sent does not carry it.
  static Future<bool> enqueueAdd(StudyPeriod period, {OutboxService? outbox}) {
    return (outbox ?? OutboxService.instance).enqueue(
      type: addType,
      method: 'POST',
      endpoint: endpoint(period.userId),
      body: {'userId': period.userId, ...period.toCreateBody()},
      dedupeKey: key(period.userId, period.clientId),
    );
  }

  // Queues "turn off" of a period the back already has: DELETE /users/{userId}/study-mode/{id}
  // (the back answers 204 also when it does not exist, so repeating it is harmless)
  static Future<bool> enqueueRemove(int userId, String clientId, int serverId, {OutboxService? outbox}) {
    return (outbox ?? OutboxService.instance).enqueue(
      type: removeType,
      method: 'DELETE',
      endpoint: periodEndpoint(userId, serverId),
      dedupeKey: key(userId, clientId),
    );
  }

  // Returns true when the back has the period (the outbox then deletes the row) or refused it for good
  static Future<bool> _send(
    Map<String, dynamic> row,
    OutboxService outbox,
    StudyPeriodDao dao,
    Future<http.Response> Function(String path, Map<String, dynamic> body) post,
    Future<http.Response> Function(String path) get,
    Future<http.Response> Function(String path) delete,
  ) async {
    final stored = jsonDecode(row['body'] as String) as Map<String, dynamic>;
    final userId = (stored['userId'] as num).toInt();
    final clientId = stored['clientId'] as String;
    final body = {
      'startTime': stored['startTime'],
      'endTime': stored['endTime'],
      'gapId': stored['gapId'],
      'clientId': clientId,
    };

    final res = await post(endpoint(userId), body);

    int? serverId;
    if (res.statusCode == 201 || res.statusCode == 200) {
      final json = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      serverId = (json['id'] as num?)?.toInt();
    } else if (res.statusCode == 409) {
      // The back already had it (a retry whose answer was lost): its id is looked up in the list
      serverId = await _findServerId(userId, clientId, get);
    } else if (OutboxService.isFinalRefusal(res.statusCode)) {
      // 400, 404, 422...: trying again never passes, so the row is dropped and the screen is told why
      await outbox.recordRefusal(row, plainBackendText(utf8.decode(res.bodyBytes, allowMalformed: true), refusedMessage));
      return true;
    } else {
      throw Exception('HTTP ${res.statusCode}');
    }

    // The user turned it off while it was being sent: the row was cancelled, so the back must forget it.
    // (If this delete fails the period stays in the back until it ends, 12 hours at most.)
    if (!await outbox.hasSameBody(row)) {
      if (serverId != null) await delete(periodEndpoint(userId, serverId));
      return true;
    }

    await dao.markSynced(clientId, serverId);
    return true;
  }

  // The id the back gave to a period: GET /users/{userId}/study-mode and look for its client id
  static Future<int?> _findServerId(
    int userId,
    String clientId,
    Future<http.Response> Function(String path) get,
  ) async {
    final res = await get(endpoint(userId));
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final list = jsonDecode(utf8.decode(res.bodyBytes)) as List;
    for (final item in list) {
      final json = item as Map<String, dynamic>;
      if (json['clientId'] == clientId) return (json['id'] as num?)?.toInt();
    }
    return null;
  }
}
