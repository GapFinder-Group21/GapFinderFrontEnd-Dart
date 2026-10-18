import 'dart:convert';
import '../core/api_client.dart';
import '../models/user.dart';

class NearbyFriendsService {
  // Get accepted friends currently in the user's current building - GET /nearby-friends/user/{userId}
  Future<List<User>> getNearbyFriends(int userId) async {
    final res = await ApiClient.get('/nearby-friends/user/$userId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting nearby friends'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => User.fromJson(json)).toList();
  }

  // Update user location from GPS coordinates and get nearby friends - PUT /nearby-friends/user/{userId}/location?latitude=...&longitude=...
  Future<List<User>> updateLocationByCoordinates(int userId, double latitude, double longitude) async {
    final res = await ApiClient.put(
      '/nearby-friends/user/$userId/location?latitude=$latitude&longitude=$longitude',
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating location by coordinates'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => User.fromJson(json)).toList();
  }

  // Update user's current building directly and get nearby friends - PUT /nearby-friends/user/{userId}/building/{buildingId}
  Future<List<User>> updateLocationByBuilding(int userId, int buildingId) async {
    final res = await ApiClient.put(
      '/nearby-friends/user/$userId/building/$buildingId',
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating location by building'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => User.fromJson(json)).toList();
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
