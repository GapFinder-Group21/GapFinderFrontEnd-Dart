import 'package:http/http.dart' as http;
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';

// Sends one request to the back (replaced in tests)
typedef AppSessionPost = Future<http.Response> Function(String endpoint, Map<String, dynamic> body);

// Saves an action to send it later (replaced in tests)
typedef AppSessionEnqueue = Future<void> Function(String endpoint, Map<String, dynamic> body);

class AppSessionService {
  final AppSessionPost _post;
  final AppSessionEnqueue _enqueueAction;
  final bool Function() _isOnline;

  AppSessionService({
    AppSessionPost? post,
    AppSessionEnqueue? enqueue,
    bool Function()? isOnline,
  })  : _post = post ?? ((endpoint, body) => ApiClient.post(endpoint, body: body)),
        _enqueueAction = enqueue ??
            ((endpoint, body) async {
              await OutboxService.instance.enqueue(type: 'app_session', method: 'POST', endpoint: endpoint, body: body);
            }),
        _isOnline = isOnline ?? (() => ConnectivityService.instance.isOnline);

  // The body of the request: the time the phone saw, in local time without zone (what the back reads).
  // An opening that waits in the outbox is sent later, so the time must travel with it.
  static Map<String, dynamic> openedAtBody(DateTime openedAt) => {'openedAt': openedAt.toIso8601String()};

  // Registers that the user opened the app - POST /app-sessions/user/{userId} with {"openedAt": ...}
  // Without connection (or if the network fails) it goes to the outbox with its original time and is sent later.
  // No dedupeKey: every time the app is opened is a different event.
  Future<void> registerOpen(int userId, {DateTime? openedAt}) async {
    final endpoint = '/app-sessions/user/$userId';
    // The time is taken now, before any waiting: a queued opening keeps the time it happened
    final body = openedAtBody(openedAt ?? DateTime.now());

    if (!_isOnline()) {
      await _enqueueAction(endpoint, body);
      return;
    }

    final http.Response res;
    try {
      res = await _post(endpoint, body);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await _enqueueAction(endpoint, body);
      return;
    }

    if (res.statusCode != 201) {
      throw Exception('Error registering app open: ${res.statusCode}');
    }
  }
}
