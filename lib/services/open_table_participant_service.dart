import 'dart:convert';
import '../core/api_client.dart';
import '../models/open_table_participant.dart';

class OpenTableParticipantService {
  // Get all participant records - GET /open-table-participants
  Future<List<OpenTableParticipant>> getAll() async {
    final res = await ApiClient.get('/open-table-participants');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting participants'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => OpenTableParticipant.fromJson(json)).toList();
  }

  // Get a participant record by its id - GET /open-table-participants/{id}
  Future<OpenTableParticipant> getParticipant(int id) async {
    final res = await ApiClient.get('/open-table-participants/$id');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting participant'));
    }

    return OpenTableParticipant.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Get the participants of an open table - GET /open-table-participants/table/{tableId}
  Future<List<OpenTableParticipant>> getByOpenTable(int tableId) async {
    final res = await ApiClient.get('/open-table-participants/table/$tableId');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting participants of the table'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => OpenTableParticipant.fromJson(json)).toList();
  }

  // A user joins an open table - POST /open-table-participants/table/{tableId}/join?userId=
  Future<OpenTableParticipant> join(int tableId, int userId) async {
    final res = await ApiClient.post(
      '/open-table-participants/table/$tableId/join?userId=$userId',
    );

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error joining the table'));
    }

    return OpenTableParticipant.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // A user leaves an open table - DELETE /open-table-participants/table/{tableId}/leave?userId=
  Future<void> leave(int tableId, int userId) async {
    final res = await ApiClient.delete(
      '/open-table-participants/table/$tableId/leave?userId=$userId',
    );

    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res, 'Error leaving the table'));
    }
  }

  // Create a new participant record - POST /open-table-participants
  // Manda openTableId y userId planos; el back aplica las mismas reglas que join(), mejor usar join()
  Future<OpenTableParticipant> createParticipant(OpenTableParticipant participant) async {
    final res = await ApiClient.post('/open-table-participants', body: participant.toJson());

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error creating participant'));
    }

    return OpenTableParticipant.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Update an existing participant record - PUT /open-table-participants/{id}
  // Solo el mismo participante puede cambiar su registro (si no, 403)
  Future<OpenTableParticipant> updateParticipant(int id, OpenTableParticipant participant) async {
    final res = await ApiClient.put('/open-table-participants/$id', body: participant.toJson());

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating participant'));
    }

    return OpenTableParticipant.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Delete a participant record - DELETE /open-table-participants/{id}
  Future<void> deleteParticipant(int id) async {
    final res = await ApiClient.delete('/open-table-participants/$id');

    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res, 'Error deleting participant'));
    }
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
