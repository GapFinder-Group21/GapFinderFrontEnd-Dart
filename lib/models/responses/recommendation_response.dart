import 'package:gapfinderfrontend_dart/models/open_table.dart';

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
