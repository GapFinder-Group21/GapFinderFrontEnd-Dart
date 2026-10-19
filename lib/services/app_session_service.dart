import 'package:http/http.dart' as http;
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';

class AppSessionService {
  // Registers that the user opened the app - POST /app-sessions/user/{userId}
  // Without connection (or if the network fails) it goes to the outbox and is sent later.
  // No dedupeKey: every time the app is opened is a different event.
  Future<void> registerOpen(int userId) async {
    final endpoint = '/app-sessions/user/$userId';

    if (!ConnectivityService.instance.isOnline) {
      await _enqueue(endpoint);
      return;
    }

    final http.Response res;
    try {
      res = await ApiClient.post(endpoint);
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await _enqueue(endpoint);
      return;
    }

    if (res.statusCode != 201) {
      throw Exception('Error registering app open: ${res.statusCode}');
    }
  }

  Future<void> _enqueue(String endpoint) async {
    await OutboxService.instance.enqueue(type: 'app_session', method: 'POST', endpoint: endpoint);
  }
}
