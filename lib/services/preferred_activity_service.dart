import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/models/responses/preferred_activity_response.dart';

// BQ 6 (type 2): the activity the user chooses most often when creating open tables
class PreferredActivityService {
  // GET /analytics/preferred-activity/user/{userId}
  // No preferred activity (the user has no open tables) is a normal answer, not an error.
  // The back answers 404 when nobody has created an open table with an activity yet, which is the same case.
  Future<PreferredActivityResponse> getPreferredActivity(int userId) async {
    final res = await ApiClient.get('/analytics/preferred-activity/user/$userId');

    if (res.statusCode == 404) return const PreferredActivityResponse.none();

    if (res.statusCode != 200) {
      throw Exception('Error getting the preferred activity: ${res.statusCode}');
    }

    return PreferredActivityResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }
}
