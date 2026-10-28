import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/miguel_local_cache.dart';
import 'package:gapfinderfrontend_dart/data/local/miguel/onboarding_prefs.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';
import 'package:gapfinderfrontend_dart/services/interest_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';

// State and logic of the interests onboarding step
class InterestsViewModel extends ChangeNotifier {
  final InterestService _interestService;
  final UserService _userService;
  final MiguelLocalCache _localCache;

  InterestsViewModel({InterestService? interestService, UserService? userService, MiguelLocalCache? localCache})
      : _interestService = interestService ?? InterestService(),
        _userService = userService ?? UserService(),
        _localCache = localCache ?? MiguelLocalCache.instance;

  List<Interest> _interests = [];
  final Set<int> _selectedInterestIds = {};
  bool _isLoading = true;
  String? _loadError;
  bool _isSaving = false;
  String? _errorMessage;
  bool _disposed = false;

  List<Interest> get interests => _interests;
  bool get isLoading => _isLoading;
  String? get loadError => _loadError;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  bool isSelected(int id) => _selectedInterestIds.contains(id);

  // Load the list of interests from the backend
  Future<void> init() async {
    _localCache.advanceOnboarding(OnboardingStep.interests);
    try {
      _interests = await _interestService.getInterests();
      // Cached on network response (never blocks the screen)
      _localCache.saveInterestsCatalog(_interests);
    } catch (e) {
      _loadError = '$e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  // Select or unselect an interest
  void toggleInterest(int id) {
    if (_selectedInterestIds.contains(id)) {
      _selectedInterestIds.remove(id);
    } else {
      _selectedInterestIds.add(id);
    }
    _notify();
  }

  // Saves the selected interests; returns true when all were saved
  Future<bool> save() async {
    _errorMessage = null;

    if (_selectedInterestIds.isEmpty) {
      _errorMessage = 'Please select at least one interest';
      return false;
    }

    _isSaving = true;
    _notify();

    // The interests the back already received (saved with synced = 1)
    final sent = <int>{};
    int? savedUserId;

    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) throw Exception('User session not found');
      savedUserId = userId;

      // Save each selected interest one by one - POST /users/{userId}/interests/{interestId}
      for (final interestId in _selectedInterestIds) {
        await _userService.addInterest(userId, interestId);
        sent.add(interestId);
      }
      _localCache.advanceOnboarding(OnboardingStep.scheduleSetup);
      return true;
    } catch (e) {
      _errorMessage = 'Error saving interests: $e';
      return false;
    } finally {
      // The chosen interests are kept in SQLite, with synced = 1 only for the ones that were sent
      if (savedUserId != null) {
        _localCache.saveUserInterests(savedUserId, Set.of(_selectedInterestIds), sent);
      }
      _isSaving = false;
      _notify();
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
