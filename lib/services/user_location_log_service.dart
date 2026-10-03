import 'dart:convert';
import '../core/api_client.dart';
import '../models/user_location_log.dart';
import '../models/building.dart';
import '../models/building_time.dart';

class UserLocationLogService {
  // Records a location checkpoint during a gap - POST /user-location-logs?userId=...&gapId=...&latitude=...&longitude=...
  Future<UserLocationLog> create(int userId, int gapId, double latitude, double longitude) async {
    final res = await ApiClient.post('/user-location-logs?userId=$userId&gapId=$gapId&latitude=$latitude&longitude=$longitude');

    if (res.statusCode != 201) {
      throw Exception('Error creating checkpoint: ${res.statusCode}');
    }

    return UserLocationLog.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Lists a gap's checkpoints in chronological order - GET /user-location-logs/gap/{gapId}
  Future<List<UserLocationLog>> getAllByGap(int gapId) async {
    final res = await ApiClient.get('/user-location-logs/gap/$gapId');

    if (res.statusCode != 200) {
      throw Exception('Error getting checkpoints: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => UserLocationLog.fromJson(json)).toList();
  }

  // Calculates minutes spent per building during a gap - GET /user-location-logs/gap/{gapId}/time-per-building
  Future<List<BuildingTime>> getTimePerBuilding(int gapId) async {
    final res = await ApiClient.get('/user-location-logs/gap/$gapId/time-per-building');

    if (res.statusCode != 200) {
      throw Exception('Error getting time per building: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => BuildingTime.fromJson(json)).toList();
  }

  // Gets the building where a user spends the most time overall - GET /user-location-logs/user/{userId}/favorite-building
  Future<Building?> getFavoriteBuilding(int userId) async {
    final res = await ApiClient.get('/user-location-logs/user/$userId/favorite-building');

    if (res.statusCode != 200) {
      throw Exception('Error getting favorite building: ${res.statusCode}');
    }

    final body = utf8.decode(res.bodyBytes);
    if (body.isEmpty || body == 'null') return null;

    return Building.fromJson(jsonDecode(body));
  }

  // Gets the building where a user spent the most time during a gap - GET /user-location-logs/gap/{gapId}/top-building
  Future<Building?> getTopBuildingForGap(int gapId) async {
    final res = await ApiClient.get('/user-location-logs/gap/$gapId/top-building');

    if (res.statusCode != 200) {
      throw Exception('Error getting top building: ${res.statusCode}');
    }

    final body = utf8.decode(res.bodyBytes);
    if (body.isEmpty || body == 'null') return null;

    return Building.fromJson(jsonDecode(body));
  }
}