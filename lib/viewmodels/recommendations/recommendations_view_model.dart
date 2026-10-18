import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/models/responses/recommendation_response.dart';
import 'package:gapfinderfrontend_dart/services/recommendation_service.dart';

// State of the suggestions tab
class RecommendationsViewModel extends ChangeNotifier {
  final RecommendationService _recommendationService;

  RecommendationsViewModel({RecommendationService? recommendationService})
      : _recommendationService = recommendationService ?? RecommendationService();

  RecommendationResponse? _recommendation;
  bool _isLoading = true;
  String? _loadError;
  bool _disposed = false;

  RecommendationResponse? get recommendation => _recommendation;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  // Load the recommendations when the screen opens
  Future<void> init() => refresh();

  // Reload everything (pull to refresh and when the tab opens again)
  Future<void> refresh() async {
    _isLoading = true;
    _loadError = null;
    _notify();

    try {
      _recommendation = await _loadRecommendations();
    } catch (e) {
      _loadError = '$e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // Gets the favorite building and the recommended tables - GET /recommendations/user/{userId}/open-tables
  Future<RecommendationResponse> _loadRecommendations() async {
    final userId = await TokenStorage.getUserId();
    if (userId == null) {
      throw Exception('No user session found');
    }
    return _recommendationService.recommendOpenTables(userId);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
