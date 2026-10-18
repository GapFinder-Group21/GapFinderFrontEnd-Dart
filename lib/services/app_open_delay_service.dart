import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/models/responses/app_open_delay_response.dart';

class AppOpenDelayService {
  // Minutes to use when the back cannot answer
  static const defaultOffsetMinutes = 5;

  // Gets how long after a gap starts the user usually opens the app - GET /analytics/app-open-delay/user/{userId}
  Future<AppOpenDelayResponse> getAppOpenDelay(int userId) async {
    final res = await ApiClient.get('/analytics/app-open-delay/user/$userId');

    if (res.statusCode != 200) {
      throw Exception('Error getting app open delay: ${res.statusCode}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return AppOpenDelayResponse.fromJson(data);
  }

  // Same as getAppOpenDelay, but returns only the offset and falls back to 5 minutes on any error
  Future<int> getOffsetMinutes(int userId) async {
    try {
      return (await getAppOpenDelay(userId)).offsetMinutes;
    } catch (_) {
      return defaultOffsetMinutes;
    }
  }
}
