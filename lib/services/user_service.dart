import 'dart:convert';
import '../core/api_client.dart';
import '../models/user.dart';

class UserService {
  // Get all users - GET /users
  Future<List<User>> getUsers() async {
    final res = await ApiClient.get('/users');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting users'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => User.fromJson(json)).toList();
  }

  // Get a user by its id - GET /users/{id}
  Future<User> getUser(int id) async {
    final res = await ApiClient.get('/users/$id');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting user'));
    }

    return User.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Create a new user - POST /users
  Future<User> createUser(User user) async {
    final res = await ApiClient.post('/users', body: user.toJson());

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error creating user'));
    }

    return User.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Update an existing user - PUT /users/{id}
  Future<User> updateUser(int id, User user) async {
    final res = await ApiClient.put('/users/$id', body: user.toJson());

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating user'));
    }

    return User.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Delete a user - DELETE /users/{id}
  Future<void> deleteUser(int id) async {
    final res = await ApiClient.delete('/users/$id');

    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res, 'Error deleting user'));
    }
  }

  // Add an interest to a user - POST /users/{userId}/interests/{interestId}
  Future<void> addInterest(int userId, int interestId) async {
    final res = await ApiClient.post('/users/$userId/interests/$interestId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error adding interest'));
    }
  }

  // Update the GPS location - PATCH /users/{userId}/location/gps
  Future<void> updateLocationByGps(int userId, double latitude, double longitude) async {
    final res = await ApiClient.patch(
      '/users/$userId/location/gps?latitude=$latitude&longitude=$longitude',
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating location'));
    }
  }

  // Search users by name - GET /users/search?name={name}
  Future<List<User>> searchByName(String name) async {
    final res = await ApiClient.get('/users/search?name=${Uri.encodeComponent(name)}');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error searching users'));
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
