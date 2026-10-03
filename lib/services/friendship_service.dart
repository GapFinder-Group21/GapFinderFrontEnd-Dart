import 'dart:convert';
import '../core/api_client.dart';
import '../models/friendship.dart';
import '../models/friendship_status_enum.dart';
import '../models/user.dart';

class FriendshipService {
  // Get all friendships - GET /friendships
  Future<List<Friendship>> getFriendships() async {
    final res = await ApiClient.get('/friendships');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting friendships'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Friendship.fromJson(json)).toList();
  }

  // Get a friendship by id - GET /friendships/{id}
  Future<Friendship> getFriendship(int id) async {
    final res = await ApiClient.get('/friendships/$id');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting friendship'));
    }

    return Friendship.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Get a user's accepted friends - GET /friendships/user/{userId}/friends
  Future<List<User>> getFriendsByUser(int userId) async {
    final res = await ApiClient.get('/friendships/user/$userId/friends');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting friends'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => User.fromJson(json)).toList();
  }

  // Pending requests received by the user (filtered on the client)
  // GET /friendships trae las de todos, así que se descartan las ajenas
  Future<List<Friendship>> getPendingReceived(int userId) async {
    final all = await getFriendships();
    return all
        .where((f) =>
    f.receiverId == userId && f.status == FriendshipStatusEnum.pending)
        .toList();
  }

  // Send a friend request (backend sets PENDING) - POST /friendships
  // Requiere requesterId y receiverId en FriendshipBasicDTO
  Future<Friendship> sendRequest(int requesterId, int receiverId) async {
    final res = await ApiClient.post('/friendships', body: {
      'requesterId': requesterId,
      'receiverId': receiverId,
    });

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error sending friend request'));
    }

    return Friendship.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Accept a friend request - PATCH /friendships/{id}/accept?userId={userId}
  Future<Friendship> acceptRequest(int id, int userId) async {
    final res = await ApiClient.patch('/friendships/$id/accept?userId=$userId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error accepting friend request'));
    }

    return Friendship.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Reject a friend request - PATCH /friendships/{id}/reject?userId={userId}
  Future<Friendship> rejectRequest(int id, int userId) async {
    final res = await ApiClient.patch('/friendships/$id/reject?userId=$userId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error rejecting friend request'));
    }

    return Friendship.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Delete a friendship - DELETE /friendships/{id}
  Future<void> delete(int id) async {
    final res = await ApiClient.delete('/friendships/$id');

    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res, 'Error deleting friendship'));
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