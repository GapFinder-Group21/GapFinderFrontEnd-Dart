import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/user_interests_dao.dart';

// Saving the interests is one POST per interest, not a single request, so the outbox cannot send
// it alone: this handler does it. The queued row body is {"userId": 1, "interestIds": [1, 2]} and
// its dedupe key is user_interests_save:<userId>, so the last selection replaces the pending one.
class UserInterestsOutbox {
  static const type = 'user_interests_save';

  static String key(int userId) => 'user_interests_save:$userId';

  // Connects the handler to the outbox (called from registerOutboxHandlers)
  static void register({OutboxService? outbox, UserInterestsDao? dao}) {
    (outbox ?? OutboxService.instance).registerHandler(type, (row) => _send(row, dao ?? UserInterestsDao()));
  }

  // Queues the selection; a pending one of the same user is replaced
  static Future<bool> enqueue(int userId, Set<int> interestIds, {OutboxService? outbox}) {
    return (outbox ?? OutboxService.instance).enqueue(
      type: type,
      method: 'POST',
      endpoint: '/users/$userId/interests',
      body: {'userId': userId, 'interestIds': (interestIds.toList()..sort())},
      dedupeKey: key(userId),
      replaceIfPending: true,
    );
  }

  // Returns true when the back has all the interests (the outbox then deletes the row)
  static Future<bool> _send(Map<String, dynamic> row, UserInterestsDao dao) async {
    final body = jsonDecode(row['body'] as String) as Map<String, dynamic>;
    final userId = body['userId'] as int;
    final ids = (body['interestIds'] as List).cast<int>().toSet();

    for (final id in ids) {
      // POST /users/{userId}/interests/{interestId}; 409 means the back already had it
      final res = await ApiClient.post('/users/$userId/interests/$id');
      if (res.statusCode != 200 && res.statusCode != 409) throw Exception('HTTP ${res.statusCode}');
    }

    await dao.replaceAllForUser(userId, ids, ids);
    return true;
  }
}
