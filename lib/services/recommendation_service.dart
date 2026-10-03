import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';
import '../models/open_table.dart';

class RecommendationResponse {
  final int? buildingId;
  final String? buildingName;
  final double totalMinutes;
  final List<OpenTable> tables;

  RecommendationResponse({
    this.buildingId,
    this.buildingName,
    required this.totalMinutes,
    required this.tables,
  });

  factory RecommendationResponse.fromJson(Map<String, dynamic> json) {
    return RecommendationResponse(
      buildingId: json['favoriteBuildingId'],
      buildingName: json['favoriteBuildingName'],
      totalMinutes: (json['totalMinutes'] as num?)?.toDouble() ?? 0.0,
      tables: (json['openTables'] as List?)
          ?.map((t) => OpenTable.fromJson(t))
          .toList() ?? [],
    );
  }
}

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
