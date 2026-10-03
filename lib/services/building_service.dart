import 'dart:convert';
import '../core/api_client.dart';
import '../models/building.dart';

class BuildingService {
  // Get all buildings - GET /buildings
  Future<List<Building>> getBuildings() async {
    final res = await ApiClient.get('/buildings');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting buildings'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Building.fromJson(json)).toList();
  }

  // Get a building by id - GET /buildings/{id}
  Future<Building> getBuilding(int id) async {
    final res = await ApiClient.get('/buildings/$id');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting building'));
    }

    return Building.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Find the building containing the coordinates - GET /buildings/locate
  // Returns null when the point is outside every building (404)
  Future<Building?> locateBuilding(double latitude, double longitude) async {
    final res = await ApiClient.get(
      '/buildings/locate?latitude=$latitude&longitude=$longitude',
    );

    if (res.statusCode == 404) return null;

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error locating building'));
    }

    return Building.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Create a new building - POST /buildings
  Future<Building> createBuilding(Building building) async {
    final res = await ApiClient.post('/buildings', body: building.toJson());

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error creating building'));
    }

    return Building.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Update an existing building - PUT /buildings/{id}
  Future<Building> updateBuilding(int id, Building building) async {
    final res = await ApiClient.put('/buildings/$id', body: building.toJson());

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating building'));
    }

    return Building.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Delete a building - DELETE /buildings/{id}
  Future<void> deleteBuilding(int id) async {
    final res = await ApiClient.delete('/buildings/$id');

    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res, 'Error deleting building'));
    }
  }

  // The back sends errors as plain text (400/404/409) or as JSON {"error": "..."} (409)
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