import 'dart:convert';
import '../core/api_client.dart';
import '../models/group.dart';

class GroupService {
  // Gets all groups - GET /groups
  Future<List<Group>> getGroups() async {
    final res = await ApiClient.get('/groups');

    if (res.statusCode != 200) {
      throw Exception('Error getting groups: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Group.fromJson(json)).toList();
  }

  // Gets a user's groups - GET /groups/user?userId=...
  Future<List<Group>> getGroupsByUser(int userId) async {
    final res = await ApiClient.get('/groups/user?userId=$userId');

    if (res.statusCode != 200) {
      throw Exception('Error getting user groups: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Group.fromJson(json)).toList();
  }

  // Gets a group by id - GET /groups/{id}
  Future<Group> getGroup(int id) async {
    final res = await ApiClient.get('/groups/$id');

    if (res.statusCode != 200) {
      throw Exception('Error getting group: ${res.statusCode}');
    }

    return Group.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Creates a new group - POST /groups?creatorId=...
  Future<Group> createGroup(int creatorId, Group group) async {
    final res = await ApiClient.post('/groups?creatorId=$creatorId', body: group.toJson());

    if (res.statusCode != 201) {
      throw Exception('Error creating group: ${res.statusCode}');
    }

    return Group.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Updates an existing group - PUT /groups/{id}
  Future<Group> updateGroup(int id, Group group) async {
    final res = await ApiClient.put('/groups/$id', body: group.toJson());

    if (res.statusCode != 200) {
      throw Exception('Error updating group: ${res.statusCode}');
    }

    return Group.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Deletes a group - DELETE /groups/{id}
  Future<void> deleteGroup(int id) async {
    final res = await ApiClient.delete('/groups/$id');

    if (res.statusCode != 204) {
      throw Exception('Error deleting group: ${res.statusCode}');
    }
  }

  // Invites (adds) a friend as a group member - POST /groups/{id}/members?requesterId=...&newMemberId=...
  Future<Group> addMember(int id, int requesterId, int newMemberId) async {
    final res = await ApiClient.post('/groups/$id/members?requesterId=$requesterId&newMemberId=$newMemberId');

    if (res.statusCode != 200) {
      throw Exception('Error adding member: ${res.statusCode}');
    }

    return Group.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }
}
