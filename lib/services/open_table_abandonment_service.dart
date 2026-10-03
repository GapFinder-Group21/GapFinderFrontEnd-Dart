import 'dart:convert';
import '../core/api_client.dart';
import '../models/open_table_abandonment.dart';
import '../models/open_table_abandonment_stats.dart';

class OpenTableAbandonmentService {
  // Registers where the user abandoned the creation form - POST /open-table-abandonments/user/{userId}
  Future<void> createAbandonment(OpenTableAbandonment abandonment) async {
    final res = await ApiClient.post(
      '/open-table-abandonments/user/${abandonment.userId}',
      body: abandonment.toJson(),
    );

    if (res.statusCode != 201) {
      throw Exception('Error registering abandonment: ${res.statusCode}');
    }
  }

  // Gets abandonment stats per step since a date - GET /open-table-abandonments/stats
  Future<List<OpenTableAbandonmentStats>> getStats(DateTime since) async {
    final sinceParam = Uri.encodeQueryComponent(since.toLocal().toIso8601String());
    final res = await ApiClient.get('/open-table-abandonments/stats?since=$sinceParam');

    if (res.statusCode != 200) {
      throw Exception('Error getting abandonment stats: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => OpenTableAbandonmentStats.fromJson(json)).toList();
  }
}