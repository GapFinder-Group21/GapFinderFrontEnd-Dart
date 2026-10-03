import 'dart:convert';
import '../core/api_client.dart';
import '../models/interest.dart';

class InterestService {
  // Get all interests - GET /interests
  Future<List<Interest>> getInterests() async {
    final res = await ApiClient.get('/interests');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting interests'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => Interest.fromJson(json)).toList();
  }

  // Get an interest by its id - GET /interests/{id}
  Future<Interest> getInterest(int id) async {
    final res = await ApiClient.get('/interests/$id');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting interest'));
    }

    return Interest.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Create a new interest - POST /interests
  // El nombre es obligatorio y único ("Ya existe un interés con el nombre: ...")
  Future<Interest> createInterest(Interest interest) async {
    final res = await ApiClient.post('/interests', body: interest.toJson());

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error creating interest'));
    }

    return Interest.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Update an existing interest - PUT /interests/{id}
  Future<Interest> updateInterest(int id, Interest interest) async {
    final res = await ApiClient.put('/interests/$id', body: interest.toJson());

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating interest'));
    }

    return Interest.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Delete an interest - DELETE /interests/{id}
  Future<void> deleteInterest(int id) async {
    final res = await ApiClient.delete('/interests/$id');

    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res, 'Error deleting interest'));
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