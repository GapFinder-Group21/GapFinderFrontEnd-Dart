import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gapfinderfrontend_dart/core/network/connectivity_service.dart';
import 'package:gapfinderfrontend_dart/core/network/network_errors.dart';
import 'package:gapfinderfrontend_dart/data/local/sofia/sofia_local_cache.dart';
import 'package:gapfinderfrontend_dart/models/building.dart';
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

// EVENTUAL CONNECTIVITY JOEL: Network falling back to cache (location banner)
// Tracks the user's location, the current building and nearby friends
class CurrentLocationViewModel extends ChangeNotifier with OfflineAwareMixin {
  // Saved as the last location when the user is not in any building
  static const outsideCampus = 'Fuera del campus';

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
  StreamSubscription<bool>? _offlineSub;
  bool _disposed = false;
  // Last building saved in SharedPreferences, shown while there is no connection
  String? _lastBuildingName;
  DateTime? _lastBuildingAt;
  bool _showingLastBuilding = false;
  // Last location calculated in this session, kept in memory too (does not depend on reading the phone)
  String? _calculatedName;
  DateTime? _calculatedAt;
  // The buildings list is saved once per session, for the offline GPS backup
  bool _buildingsSaved = false;

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
    // Without internet it never shows the live building, only the last calculated one
    if (_showingLastBuilding || !hasConnection) return LocationBannerStatus.offline;
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
    // The moment the internet drops, switch to the last calculated location (no wait for the timer)
    _offlineSub = ConnectivityService.instance.onStatusChange.listen((online) {
      if (!online) _showLastBuilding();
    });
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

    // The GPS has its own try: a slow or failed GPS is not a network problem, so it must not show
    // the "last building" banner
    final Position position;
    try {
      debugPrint('DEBUG: [Banner] Requesting current GPS position...');
      position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (e) {
      debugPrint('❌ [Banner] GPS error: $e');
      if (!_disposed) {
        _isLocationEnabled = false;
        _locationCalculated = false;
        _isFirstLoad = false;
        _isRefreshing = false;
        _notify();
      }
      return;
    }

    try {

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

      // Without the part number, so moving from "Bobo 1" to "Bobo 2" is not a new building
      final newBuildingName = building?.displayName;
      debugPrint('DEBUG: [Banner] Located building name: ${newBuildingName ?? "Outside campus"}');

      // Every calculated location is kept in memory and saved (SharedPreferences), also "outside campus",
      // so without internet the banner can show the last one
      _calculatedName = newBuildingName ?? outsideCampus;
      _calculatedAt = DateTime.now();
      await SofiaLocalCache.instance.saveLastBuilding(_calculatedName!);
      _saveBuildingsForOffline();

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

  // Without internet: shows the last calculated location saved in SharedPreferences.
  // If none was ever saved, it is calculated on the phone (GPS + saved buildings). Nothing is sent to the back.
  Future<void> _showLastBuilding() async {
    // The one calculated in this session is the newest: shown at once, no read needed
    if (_calculatedName != null) {
      _lastBuildingName = _calculatedName;
      _lastBuildingAt = _calculatedAt;
    } else {
      try {
        final prefs = SofiaLocalCache.instance.lastBuilding;
        _lastBuildingName = await prefs.loadName();
        _lastBuildingAt = await prefs.loadAt();
      } catch (e) {
        debugPrint('No se pudo leer el último edificio: $e');
      }
    }

    if (_lastBuildingName == null) {
      try {
        final name = await _locateWithSavedBuildings();
        if (name != null) {
          _lastBuildingName = name;
          _lastBuildingAt = DateTime.now();
          SofiaLocalCache.instance.saveLastBuilding(name);
        }
      } catch (e) {
        debugPrint('No se pudo calcular la ubicación sin internet: $e');
      }
    }
    if (_disposed) return;
    _showingLastBuilding = true;
    _isFirstLoad = false;
    _isRefreshing = false;
    _notify();
  }

  // Saves the buildings list as a file while there is internet, so the offline GPS backup works
  // even if the create table screen was never opened. Not awaited, never breaks the banner.
  void _saveBuildingsForOffline() {
    if (_buildingsSaved) return;
    _buildingsSaved = true;
    _buildingService.getBuildings().then((buildings) async {
      if (buildings.isNotEmpty) await SofiaLocalCache.instance.catalogs.saveBuildings(buildings);
    }).catchError((Object e) {
      _buildingsSaved = false;
      debugPrint('Could not save the buildings for offline: $e');
    });
  }

  // GPS works without internet, and the buildings catalog saved as a file has each building's center
  // and radius, so the building can be found on the phone. Null if there is no GPS or no saved catalog.
  Future<String?> _locateWithSavedBuildings() async {
    if (!await LocationService.isLocationEnabled()) return null;
    final saved = await SofiaLocalCache.instance.catalogs.loadBuildings();
    if (saved == null || saved.items.isEmpty) return null;

    final position = await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
    return nameForPosition(saved.items, position.latitude, position.longitude);
  }

  // The closest building whose radius contains the point, or "outside campus"
  @visibleForTesting
  static String nameForPosition(List<Building> buildings, double lat, double lon) {
    Building? best;
    double bestDistance = double.infinity;
    for (final b in buildings) {
      final d = Geolocator.distanceBetween(lat, lon, b.latitude, b.longitude);
      if (d <= b.radiusMeters && d < bestDistance) {
        best = b;
        bestDistance = d;
      }
    }
    return best?.displayName ?? outsideCampus;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _serviceStatusSubscription?.cancel();
    _offlineSub?.cancel();
    _events.close();
    super.dispose();
  }
}
