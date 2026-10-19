import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/building_service.dart';
import 'package:gapfinderfrontend_dart/services/location_service.dart';
import 'package:gapfinderfrontend_dart/services/nearby_friends_service.dart';

// What the location banner shows
enum LocationBannerStatus { locating, disabled, inBuilding, outsideCampus, unavailable }

// Event: the user arrived to a building where some friends are
class NearbyFriendsDetected {
  final String buildingName;
  final List<User> friends;
  NearbyFriendsDetected(this.buildingName, this.friends);
}

// Tracks the user's location, the current building and nearby friends
class CurrentLocationViewModel extends ChangeNotifier {
  final int userId;
  final NearbyFriendsService _nearbyFriendsService;
  final BuildingService _buildingService;

  CurrentLocationViewModel(
    this.userId, {
    NearbyFriendsService? nearbyFriendsService,
    BuildingService? buildingService,
  })  : _nearbyFriendsService = nearbyFriendsService ?? NearbyFriendsService(),
        _buildingService = buildingService ?? BuildingService();

  final _events = StreamController<NearbyFriendsDetected>.broadcast();
  String? _buildingName;
  String? _previousBuildingName;
  bool _isFirstLoad = true;
  bool _isRefreshing = false;
  bool _isLocationEnabled = true;
  bool _locationCalculated = false;
  Timer? _timer;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;
  bool _disposed = false;

  Stream<NearbyFriendsDetected> get events => _events.stream;
  String? get buildingName => _buildingName;
  bool get isFirstLoad => _isFirstLoad;
  bool get isRefreshing => _isRefreshing;

  // What the banner should show right now
  LocationBannerStatus get status {
    if (_isFirstLoad) return LocationBannerStatus.locating;
    if (!_isLocationEnabled) return LocationBannerStatus.disabled;
    if (_locationCalculated) {
      return _buildingName != null
          ? LocationBannerStatus.inBuilding
          : LocationBannerStatus.outsideCampus;
    }
    return LocationBannerStatus.unavailable;
  }

  // Update now, every 2 minutes, and when the GPS is turned on or off
  void init() {
    updateLocation();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => updateLocation());
    _listenToLocationChanges();
  }

  void _listenToLocationChanges() {
    if (!kIsWeb) {
      _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((status) {
        debugPrint('DEBUG: [Banner] GPS Status changed to: $status');
        updateLocation();
      });
    }
  }

  Future<void> updateLocation() async {
    if (_disposed) return;
    debugPrint('DEBUG: [Banner] Starting location update for userId=$userId...');
    _isRefreshing = true;
    _notify();

    final enabled = await LocationService.isLocationEnabled();
    debugPrint('DEBUG: [Banner] Location service enabled: $enabled');
    if (!enabled) {
      if (!_disposed) {
        _isLocationEnabled = false;
        _locationCalculated = false;
        _buildingName = null;
        _isFirstLoad = false;
        _isRefreshing = false;
        _notify();
      }
      debugPrint('DEBUG: [Banner] Location is disabled or permissions denied.');
      return;
    }

    try {
      debugPrint('DEBUG: [Banner] Requesting current GPS position...');
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );

      debugPrint('📍 [Banner] LOCATION DETECTED: Lat: ${position.latitude}, Long: ${position.longitude}');

      // Call nearby-friends location update endpoint
      debugPrint('DEBUG: [Banner] Calling updateLocationByCoordinates...');
      final nearbyFriends = await _nearbyFriendsService.updateLocationByCoordinates(
        userId,
        position.latitude,
        position.longitude,
      );
      debugPrint('DEBUG: [Banner] Nearby friends response count: ${nearbyFriends.length}');

      debugPrint('DEBUG: [Banner] Locating building from coordinates...');
      final building = await _buildingService.locateBuilding(
        position.latitude,
        position.longitude,
      );

      final newBuildingName = building?.name;
      debugPrint('DEBUG: [Banner] Located building name: ${newBuildingName ?? "Outside campus"}');

      // Remember the last building the user was in (SharedPreferences); not awaited
      if (newBuildingName != null) {
        SofiaLocalCache.instance.saveLastBuilding(newBuildingName);
      }

      final buildingChanged = _previousBuildingName != newBuildingName;

      if (buildingChanged && newBuildingName != null && nearbyFriends.isNotEmpty) {
        debugPrint('DEBUG: [Banner] Building changed from "$_previousBuildingName" to "$newBuildingName" with ${nearbyFriends.length} friends nearby!');
        if (!_disposed) {
          _events.add(NearbyFriendsDetected(newBuildingName, nearbyFriends));
        }
      }

      if (!_disposed) {
        _previousBuildingName = newBuildingName;
        _isLocationEnabled = true;
        _locationCalculated = true;
        _buildingName = newBuildingName;
        _isFirstLoad = false;
        _isRefreshing = false;
        _notify();
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [Banner] Error updating location in banner: $e');
      debugPrint('$stackTrace');
      if (!_disposed) {
        _isLocationEnabled = false;
        _locationCalculated = false;
        _isFirstLoad = false;
        _isRefreshing = false;
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _serviceStatusSubscription?.cancel();
    _events.close();
    super.dispose();
  }
}
