import 'dart:convert';
import '../core/api_client.dart';
import '../models/user.dart';

class UserService {
  // Get all users - GET /users
  Future<List<User>> getUsers() async {
    final res = await ApiClient.get('/users');

    if (res.statusCode != 200) {
      throw Exception('Error getting users: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => User.fromJson(json)).toList();
  }

  // Get a user by its id - GET /users/{id}
  Future<User> getUser(int id) async {
    final res = await ApiClient.get('/users/$id');

    if (res.statusCode != 200) {
      throw Exception('Error getting user: ${res.statusCode}');
    }

    return User.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Create a new user - POST /users
  Future<User> createUser(User user) async {
    final res = await ApiClient.post('/users', body: user.toJson());

    if (res.statusCode != 201) {
      throw Exception('Error creating user: ${res.statusCode}');
    }

    return User.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Update an existing user - PUT /users/{id}
  Future<User> updateUser(int id, User user) async {
    final res = await ApiClient.put('/users/$id', body: user.toJson());

    if (res.statusCode != 200) {
      throw Exception('Error updating user: ${res.statusCode}');
    }

    return User.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Delete a user - DELETE /users/{id}
  Future<void> deleteUser(int id) async {
    final res = await ApiClient.delete('/users/$id');

    if (res.statusCode != 204) {
      throw Exception('Error deleting user: ${res.statusCode}');
    }
  }

  // Add an interest to a user - POST /users/{userId}/interests/{interestId}
  Future<void> addInterest(int userId, int interestId) async {
    final res = await ApiClient.post('/users/$userId/interests/$interestId');

    if (res.statusCode != 200) {
      throw Exception('Error adding interest: ${res.statusCode}');
    }
  }

  // Update the GPS location - PATCH /users/{userId}/location/gps
  Future<void> updateLocationByGps(int userId, double latitude, double longitude) async {
    final res = await ApiClient.patch(
      '/users/$userId/location/gps?latitude=$latitude&longitude=$longitude',
    );

    if (res.statusCode != 200) {
      throw Exception('Error updating location: ${res.statusCode}');
    }
  }

  // Search users by name - GET /users/search?name={name}
  Future<List<User>> searchByName(String name) async {
    final res = await ApiClient.get('/users/search?name=${Uri.encodeComponent(name)}');

    if (res.statusCode != 200) {
      throw Exception('Error searching users: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => User.fromJson(json)).toList();
  }
}