import 'package:flutter/foundation.dart';
import 'package:gapfinderfrontend_dart/core/storage/token_storage.dart';
import 'package:gapfinderfrontend_dart/models/interest.dart';
import 'package:gapfinderfrontend_dart/services/interest_service.dart';
import 'package:gapfinderfrontend_dart/services/user_service.dart';

// State and logic of the interests onboarding step
class InterestsViewModel extends ChangeNotifier {
  final InterestService _interestService;
  final UserService _userService;

  InterestsViewModel({InterestService? interestService, UserService? userService})
      : _interestService = interestService ?? InterestService(),
        _userService = userService ?? UserService();

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
    try {
      _interests = await _interestService.getInterests();
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

    try {
      final userId = await TokenStorage.getUserId();
      if (userId == null) throw Exception('User session not found');

      // Save each selected interest one by one - POST /users/{userId}/interests/{interestId}
      for (final interestId in _selectedInterestIds) {
        await _userService.addInterest(userId, interestId);
      }
      return true;
    } catch (e) {
      _errorMessage = 'Error saving interests: $e';
      return false;
    } finally {
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
