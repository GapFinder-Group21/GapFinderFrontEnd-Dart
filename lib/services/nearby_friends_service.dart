import 'dart:convert';
import '../core/api_client.dart';
import '../models/user.dart';

class NearbyFriendsService {
  // Get accepted friends currently in the user's current building - GET /nearby-friends/user/{userId}
  Future<List<User>> getNearbyFriends(int userId) async {
    final res = await ApiClient.get('/nearby-friends/user/$userId');

    if (res.statusCode != 200) {
      throw Exception('Error getting nearby friends: ${res.statusCode}');
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
      throw Exception('Error updating location by coordinates: ${res.statusCode}');
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
      throw Exception('Error updating location by building: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => User.fromJson(json)).toList();
  }
}
