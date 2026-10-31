import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_dao.dart';

// Saving the interests is one request per interest, not a single request, so the outbox cannot send
// it alone: this handler does it. The queued row body is
// {"userId": 1, "interestIds": [1, 2], "addIds": [2], "removeIds": [3]}: interestIds is the whole
// selection (what SQLite keeps), addIds are sent with POST and removeIds with DELETE.
// Its dedupe key is user_interests_save:<userId>, so the last selection replaces the pending one.
class UserInterestsOutbox {
  static const type = 'user_interests_save';

  // What the interests screen shows when the selection could not be saved for good
  static const saveFailedMessage = 'No pudimos guardar tus intereses. Inténtalo de nuevo';

  static String key(int userId) => 'user_interests_save:$userId';

  // Connects the handler to the outbox (called from registerOutboxHandlers)
  // post and delete are only replaced in tests
  static void register({
    OutboxService? outbox,
    UserInterestsDao? dao,
    Future<http.Response> Function(String path)? post,
    Future<http.Response> Function(String path)? delete,
  }) {
    final service = outbox ?? OutboxService.instance;
    service.registerHandler(
      type,
      (row) => _send(row, service, dao ?? UserInterestsDao(), post ?? ApiClient.post, delete ?? ApiClient.delete),
    );
  }

  // The interests that a pending selection still has to delete in the back
  static Future<Set<int>> pendingRemoveIds(int userId, {OutboxService? outbox}) async {
    final raw = await (outbox ?? OutboxService.instance).pendingBody(key(userId));
    if (raw == null) return {};
    return _ids(jsonDecode(raw) as Map<String, dynamic>, 'removeIds') ?? {};
  }

  // Queues the selection; a pending one of the same user is replaced.
  // addIds: the interests the back does not have yet (all of them if null); removeIds: the ones to delete.
  // What a replaced selection had still to delete is kept, because its row is not sent anymore.
  static Future<bool> enqueue(
    int userId,
    Set<int> interestIds, {
    Set<int>? addIds,
    Set<int> removeIds = const {},
    OutboxService? outbox,
  }) async {
    final service = outbox ?? OutboxService.instance;
    final pendingRemove = await pendingRemoveIds(userId, outbox: service);
    final remove = {...removeIds, ...pendingRemove.difference(interestIds)};

    return service.enqueue(
      type: type,
      method: 'POST',
      endpoint: '/users/$userId/interests',
      body: {
        'userId': userId,
        'interestIds': (interestIds.toList()..sort()),
        'addIds': ((addIds ?? interestIds).toList()..sort()),
        'removeIds': (remove.toList()..sort()),
      },
      dedupeKey: key(userId),
      replaceIfPending: true,
    );
  }

  static Set<int>? _ids(Map<String, dynamic> body, String field) {
    final list = body[field];
    return list == null ? null : (list as List).cast<int>().toSet();
  }

  // A final 4xx (400, 404...) never passes by trying again, so the row is dropped at once instead of using
  // the 5 attempts. SQLite keeps synced = 0 and the refusal tells the screen that saving failed.
  static Future<bool> _giveUp(Map<String, dynamic> row, OutboxService outbox) async {
    await outbox.recordRefusal(row, saveFailedMessage);
    return true;
  }

  // Returns true when the back has all the interests (the outbox then deletes the row)
  static Future<bool> _send(
    Map<String, dynamic> row,
    OutboxService outbox,
    UserInterestsDao dao,
    Future<http.Response> Function(String path) post,
    Future<http.Response> Function(String path) delete,
  ) async {
    final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
    final userId = body['userId'] as int;
    final ids = _ids(body, 'interestIds')!;
    // Rows queued before addIds / removeIds existed only have interestIds
    final add = _ids(body, 'addIds') ?? ids;
    final remove = _ids(body, 'removeIds') ?? <int>{};

    for (final id in add) {
      // POST /users/{userId}/interests/{interestId}; 409 means the back already had it
      final res = await post('/users/$userId/interests/$id');
      if (res.statusCode != 200 && res.statusCode != 409) {
        if (OutboxService.isFinalRefusal(res.statusCode)) return _giveUp(row, outbox);
        throw Exception('HTTP ${res.statusCode}');
      }
    }

    for (final id in remove) {
      // DELETE /users/{userId}/interests/{interestId}; 204 also when the back did not have it
      final res = await delete('/users/$userId/interests/$id');
      if (res.statusCode != 204 && res.statusCode != 200) {
        if (OutboxService.isFinalRefusal(res.statusCode)) return _giveUp(row, outbox);
        throw Exception('HTTP ${res.statusCode}');
      }
    }

    // If the user saved another selection while this one was being sent, SQLite already has the newer
    // one: writing the old one over it would lose it
    if (await outbox.hasSameBody(row)) await dao.replaceAllForUser(userId, ids, ids);
    return true;
  }
}
