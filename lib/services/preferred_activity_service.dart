import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/models/responses/preferred_activity_response.dart';

// The back does not know the user (404): it says nothing about their favorite activity
class PreferredActivityUnknownUserException implements Exception {
  final int userId;
  PreferredActivityUnknownUserException(this.userId);

  @override
  String toString() => 'Unknown user $userId for the preferred activity';
}

// BQ 6 (type 2): the activity the user chooses most often when creating open tables
class PreferredActivityService {
  // GET /analytics/preferred-activity/user/{userId}
  // No preferred activity (the user has no open tables) is a normal 200 answer with userPreferredActivity = null.
  // A 404 means the back does not know the user: it is thrown, so the saved favorite is kept.
  Future<PreferredActivityResponse> getPreferredActivity(int userId) async {
    final res = await ApiClient.get('/analytics/preferred-activity/user/$userId');

    if (res.statusCode == 404) throw PreferredActivityUnknownUserException(userId);

    if (res.statusCode != 200) {
      throw Exception('Error getting the preferred activity: ${res.statusCode}');
    }

    return PreferredActivityResponse.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }
}
