import 'dart:convert';
import '../core/api_client.dart';
import '../models/class_block.dart';

class ClassBlockService {
  // Gets a class block by id - GET /class-blocks/{id}
  Future<ClassBlock> getClassBlock(int id) async {
    final res = await ApiClient.get('/class-blocks/$id');

    if (res.statusCode != 200) {
      throw Exception('Error getting class block: ${res.statusCode}');
    }

    return ClassBlock.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Gets a user's full schedule - GET /class-blocks/user/{userId}
  Future<List<ClassBlock>> getByUser(int userId) async {
    final res = await ApiClient.get('/class-blocks/user/$userId');

    if (res.statusCode != 200) {
      throw Exception('Error getting schedule: ${res.statusCode}');
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => ClassBlock.fromJson(json)).toList();
  }

  // Adds a class block to a user's schedule - POST /class-blocks/user/{userId}
  Future<ClassBlock> createClassBlock(int userId, ClassBlock classBlock) async {
    final res = await ApiClient.post('/class-blocks/user/$userId', body: classBlock.toJson());

    if (res.statusCode != 201) {
      throw Exception('Error creating class block: ${res.statusCode}');
    }

    return ClassBlock.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Updates an existing class block - PUT /class-blocks/{id}
  Future<ClassBlock> updateClassBlock(int id, ClassBlock classBlock) async {
    final res = await ApiClient.put('/class-blocks/$id', body: classBlock.toJson());

    if (res.statusCode != 200) {
      throw Exception('Error updating class block: ${res.statusCode}');
    }

    return ClassBlock.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Deletes a class block - DELETE /class-blocks/{id}
  Future<void> deleteClassBlock(int id) async {
    final res = await ApiClient.delete('/class-blocks/$id');

    if (res.statusCode != 204) {
      throw Exception('Error deleting class block: ${res.statusCode}');
    }
  }
}
