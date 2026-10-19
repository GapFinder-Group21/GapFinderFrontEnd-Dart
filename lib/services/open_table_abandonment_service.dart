import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/core/storage/outbox_service.dart';
import 'package:gapfinderfrontend_dart/models/open_table_abandonment.dart';
import 'package:gapfinderfrontend_dart/models/responses/open_table_abandonment_stats.dart';

class OpenTableAbandonmentService {
  // Registers where the user abandoned the creation form - POST /open-table-abandonments/user/{userId}
  // Without connection (or if the network fails) the report goes to the outbox and is sent later.
  // The dedupeKey makes sure the same abandonment is never sent twice.
  Future<void> createAbandonment(OpenTableAbandonment abandonment, {String? dedupeKey}) async {
    final endpoint = '/open-table-abandonments/user/${abandonment.userId}';

    if (!ConnectivityService.instance.isOnline) {
      await _enqueue(endpoint, abandonment, dedupeKey);
      return;
    }

    final http.Response res;
    try {
      res = await ApiClient.post(endpoint, body: abandonment.toJson());
    } catch (e) {
      if (!isNetworkError(e)) rethrow;
      await _enqueue(endpoint, abandonment, dedupeKey);
      return;
    }

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error registering abandonment'));
    }
  }

  Future<void> _enqueue(String endpoint, OpenTableAbandonment abandonment, String? dedupeKey) async {
    await OutboxService.instance.enqueue(
      type: 'open_table_abandonment',
      method: 'POST',
      endpoint: endpoint,
      body: abandonment.toJson(),
      dedupeKey: dedupeKey,
    );
  }

  // Gets abandonment stats per step since a date - GET /open-table-abandonments/stats
  Future<List<OpenTableAbandonmentStats>> getStats(DateTime since) async {
    final sinceParam = Uri.encodeQueryComponent(since.toLocal().toIso8601String());
    final res = await ApiClient.get('/open-table-abandonments/stats?since=$sinceParam');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting abandonment stats'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => OpenTableAbandonmentStats.fromJson(json)).toList();
  }

  // The back sends errors as plain text (400/403/404/409) or as JSON {"error": "..."} (409)
  String _errorMessage(dynamic res, String fallback) {
    final body = utf8.decode(res.bodyBytes).trim();
    if (body.isEmpty) return '$fallback: ${res.statusCode}';

    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['error'] != null) {
        return decoded['error'].toString();
      }
    } catch (_) {
      // Not JSON, it is plain text
    }
    return body;
  }
}
