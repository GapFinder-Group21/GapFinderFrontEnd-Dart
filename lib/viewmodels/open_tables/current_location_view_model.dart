import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/user.dart';
import 'package:gapfinderfrontend_dart/services/building_service.dart';
import 'package:gapfinderfrontend_dart/services/location_service.dart';
import 'package:gapfinderfrontend_dart/services/nearby_friends_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// What the location banner shows
enum LocationBannerStatus { locating, disabled, inBuilding, outsideCampus, unavailable, offline }

// Event: the user arrived to a building where some friends are
class NearbyFriendsDetected {
  final String buildingName;
  final List<User> friends;
  NearbyFriendsDetected(this.buildingName, this.friends);
}

// Tracks the user's location, the current building and nearby friends
class CurrentLocationViewModel extends ChangeNotifier with OfflineAwareMixin {
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
  // Last building saved in SharedPreferences, shown while there is no connection
  String? _lastBuildingName;
  DateTime? _lastBuildingAt;
  bool _showingLastBuilding = false;

  Stream<NearbyFriendsDetected> get events => _events.stream;
  String? get buildingName => _buildingName;
  bool get isFirstLoad => _isFirstLoad;
  bool get isRefreshing => _isRefreshing;
  String? get lastBuildingName => _lastBuildingName;

  // "hace N min" since the last building was detected
  String get lastBuildingAgo {
    final at = _lastBuildingAt;
    if (at == null) return '';
    final minutes = DateTime.now().difference(at).inMinutes;
    if (minutes < 60) return 'hace ${minutes < 1 ? 1 : minutes} min';
    if (minutes < 24 * 60) return 'hace ${minutes ~/ 60} h';
    return 'hace ${minutes ~/ (24 * 60)} d';
  }

  // What the banner should show right now
  LocationBannerStatus get status {
    if (_showingLastBuilding) return LocationBannerStatus.offline;
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
    listenToConnectivity(onRestored: updateLocation);
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

    // Without connection the location is not sent: the last building saved is shown instead
    if (!hasConnection) {
      await _showLastBuilding();
      return;
    }
    _showingLastBuilding = false;

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
      // The connection dropped in the middle: it is not a GPS problem
      if (isNetworkError(e) || !hasConnection) {
        await _showLastBuilding();
        return;
      }
      if (!_disposed) {
        _isLocationEnabled = false;
        _locationCalculated = false;
        _isFirstLoad = false;
        _isRefreshing = false;
        _notify();
      }
    }
  }

  // Reads "last building" from SharedPreferences and shows it. Nothing is sent to the back.
  Future<void> _showLastBuilding() async {
    try {
      final prefs = SofiaLocalCache.instance.lastBuilding;
      _lastBuildingName = await prefs.loadName();
      _lastBuildingAt = await prefs.loadAt();
    } catch (e) {
      debugPrint('No se pudo leer el último edificio: $e');
    }
    if (_disposed) return;
    _showingLastBuilding = true;
    _isFirstLoad = false;
    _isRefreshing = false;
    _notify();
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
