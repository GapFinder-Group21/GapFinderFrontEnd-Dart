import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/models/open_table.dart';

class OpenTableService {
  // Get an open table by its id - GET /open-tables/{id}
  Future<OpenTable> getOpenTable(int id) async {
    final res = await ApiClient.get('/open-tables/$id');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting open table'));
    }

    return OpenTable.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Get all open tables - GET /open-tables
  // Devuelve OpenTableListDTO: incluye creator (id, name, career, avatarUrl) y building (id, name)
  Future<List<OpenTable>> getAll() async {
    final res = await ApiClient.get('/open-tables');

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error getting open tables'));
    }

    final List data = jsonDecode(utf8.decode(res.bodyBytes));
    return data.map((json) => OpenTable.fromJson(json)).toList();
  }

  // Count the open tables created since the given date - GET /open-tables/count?since=...
  Future<int> countCreatedSince(DateTime since) async {
    final res = await ApiClient.get(
      '/open-tables/count?since=${_formatDateTime(since)}',
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error counting open tables'));
    }

    return int.parse(utf8.decode(res.bodyBytes).trim());
  }

  // Create a new open table - POST /open-tables
  // Exige creator (el usuario logueado), building, title, startTime antes de endTime,
  // endTime en el futuro y maxParticipants > 0. El back siempre la crea OPEN
  // Se manda como multipart: "openTable" con los datos en JSON y "photo" con la foto (obligatoria)
  Future<OpenTable> createOpenTable(
      int creatorId, int buildingId, OpenTable openTable, File photo) async {
    final res = await ApiClient.postMultipart(
      '/open-tables',
      files: () async => [
        http.MultipartFile.fromString(
          'openTable',
          jsonEncode(_withRelations(openTable, creatorId, buildingId)),
          contentType: MediaType('application', 'json'),
        ),
        await http.MultipartFile.fromPath(
          'photo',
          photo.path,
          contentType: MediaType('image', 'jpeg'),
        ),
      ],
    );

    if (res.statusCode != 201) {
      throw Exception(_errorMessage(res, 'Error creating open table'));
    }

    return OpenTable.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Update an existing open table - PUT /open-tables/{id}
  Future<OpenTable> updateOpenTable(
      int id, int creatorId, int buildingId, OpenTable openTable) async {
    final res = await ApiClient.put(
      '/open-tables/$id',
      body: _withRelations(openTable, creatorId, buildingId),
    );

    if (res.statusCode != 200) {
      throw Exception(_errorMessage(res, 'Error updating open table'));
    }

    return OpenTable.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
  }

  // Delete an open table - DELETE /open-tables/{id}
  Future<void> deleteOpenTable(int id) async {
    final res = await ApiClient.delete('/open-tables/$id');

    if (res.statusCode != 204) {
      throw Exception(_errorMessage(res, 'Error deleting open table'));
    }
  }

  // Formato de OpenTableCompleteDTO: creator y building anidados con su id
  Map<String, dynamic> _withRelations(
      OpenTable openTable, int creatorId, int buildingId) {
    return {
      ...openTable.toJson(),
      'creator': {'id': creatorId},
      'building': {'id': buildingId},
    };
  }

  // yyyy-MM-ddTHH:mm:ss sin zona, el formato que espera "since"
  // (toIso8601String() agrega "Z" en fechas UTC y el back lo rechaza)
  String _formatDateTime(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}'
        'T${two(d.hour)}:${two(d.minute)}:${two(d.second)}';
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
    return plainBackendText(body, fallback);
  }
}