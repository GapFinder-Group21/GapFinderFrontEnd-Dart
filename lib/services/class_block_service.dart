import 'dart:convert';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/models/class_block.dart';
import 'package:gapfinderfrontend_dart/services/gap_generation_guard.dart';

class ClassBlockService {
  // Gets a class block by id - GET /class-blocks/{id}
  Future<ClassBlock> getClassBlock(int id) async {
    final res = await ApiClient.get('/class-blocks/$id');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting class block'));
    }

    return ClassBlock.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Gets a user's full schedule - GET /class-blocks/user/{userId}
  Future<List<ClassBlock>> getByUser(int userId) async {
    final res = await ApiClient.get('/class-blocks/user/$userId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting schedule'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => ClassBlock.fromJson(json)).toList();
  }

  // Adds a class block to a user's schedule - POST /class-blocks/user/{userId}
  Future<ClassBlock> createClassBlock(int userId, ClassBlock classBlock) async {
    final res = await ApiClient.post('/class-blocks/user/$userId', body: classBlock.toJson());

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error creating class block'));
    }

    // The schedule changed: the next refresh recalculates the gaps
    await GapGenerationGuard.invalidate(userId);
    return ClassBlock.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Updates an existing class block - PUT /class-blocks/{id}
  Future<ClassBlock> updateClassBlock(int id, ClassBlock classBlock) async {
    final res = await ApiClient.put('/class-blocks/$id', body: classBlock.toJson());

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating class block'));
    }

    await GapGenerationGuard.invalidateAll();
    return ClassBlock.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Deletes a class block - DELETE /class-blocks/{id}
  Future<void> deleteClassBlock(int id) async {
    final res = await ApiClient.delete('/class-blocks/$id');

    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res, 'Error deleting class block'));
    }

    // The schedule changed (the id of the user is not known here, so every user is invalidated)
    await GapGenerationGuard.invalidateAll();
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
    return plainBackendText(body, fallback);
  }
}
