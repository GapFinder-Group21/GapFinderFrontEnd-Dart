import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/recommendations_hive_store.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/responses/recommendation_response.dart';
import 'package:gapfinderfrontend_dart/services/recommendation_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// State of the suggestions tab
class RecommendationsViewModel extends ChangeNotifier with OfflineAwareMixin {
  final RecommendationService _recommendationService;

  RecommendationsViewModel({RecommendationService? recommendationService})
      : _recommendationService = recommendationService ?? RecommendationService();

  RecommendationResponse? _recommendation;
  bool _isLoading = true;
  String? _loadError;
  bool _noSavedData = false;
  bool _disposed = false;

  RecommendationResponse? get recommendation => _recommendation;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;

  // No connection and nothing was ever saved: the View shows its own message
  bool get isOfflineWithoutData => _noSavedData;

  // Load the recommendations when the screen opens; they reload by themselves when the connection comes back
  Future<void> init() {
    listenToConnectivity(onRestored: refresh);
    return refresh();
  }

  // Cache then network: shows the last answer saved in Hive right away and then updates it
  // with the network. If the network fails, the saved answer stays on screen.
  Future<void> refresh() async {
    _loadError = null;
    _noSavedData = false;
    _isLoading = _recommendation == null;
    _notify();

    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) {
        throw Exception('No user session found');
      }

      // 1. Cache: the last answer, shown immediately (only if nothing is on screen yet)
      if (_recommendation == null) {
        final saved = await _loadSaved(userId);
        if (saved != null) {
          _recommendation = saved.response;
          markUpdatedAt(saved.savedAt);
          _isLoading = false;
          _notify();
        }
      }

      // 2. Network: only when there is a connection
      if (hasConnection) {
        try {
          final fresh = await _recommendationService
              .recommendOpenTables(userId)
              .timeout(OfflineAwareMixin.loadTimeout);

          // Save what the network answered; it is not awaited and never breaks the screen
          SofiaLocalCache.instance.saveRecommendation(userId, fresh);

          _recommendation = fresh;
          markFresh();
          return;
        } catch (e) {
          debugPrint('Sin red para las recomendaciones: $e');
          if (_recommendation == null) rethrow;
          markFromCache(lastUpdated);
          return;
        }
      }

      // No connection: the saved answer stays, or the own message if there is none
      if (_recommendation != null) {
        markFromCache(lastUpdated);
      } else {
        markFromCache(null);
        _noSavedData = true;
      }
    } catch (e) {
      _loadError = '$e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // The last answer saved in Hive, or null if there is none
  Future<SavedRecommendation?> _loadSaved(int userId) async {
    try {
      return await SofiaLocalCache.instance.recommendations.load(userId);
    } catch (e) {
      debugPrint('No se pudieron leer las recomendaciones guardadas: $e');
      return null;
    }
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
