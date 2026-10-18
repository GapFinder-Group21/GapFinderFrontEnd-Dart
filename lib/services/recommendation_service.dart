import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/network/api_client.dart';
import 'package:gapfinderfrontend_dart/models/responses/recommendation_response.dart';

class RecommendationService {
  // Get recommendations for a user - GET /recommendations/user/{userId}/open-tables
  Future<RecommendationResponse> recommendOpenTables(int userId) async {
    final res = await ApiClient.get('/recommendations/user/$userId/open-tables');
    debugPrint('REC userId=$userId status=${res.statusCode} body=${utf8.decode(res.bodyBytes)}');

    if (res.statusCode != 200) {
      throw Exception('Error getting recommendations: ${res.statusCode}');
    }

    final data = jsonDecode(utf8.decode(res.bodyBytes));
    return RecommendationResponse.fromJson(data);
  }
}
