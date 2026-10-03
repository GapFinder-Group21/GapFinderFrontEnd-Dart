import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../../core/app_colors.dart';
import '../../core/app_fonts.dart';
import '../../services/location_service.dart';
import '../../services/building_service.dart';
import '../../services/nearby_friends_service.dart';
import 'nearby_friends_alert_dialog.dart';

class CurrentLocationBanner extends StatefulWidget {
  final int userId;
  const CurrentLocationBanner({super.key, required this.userId});

  @override
  State<CurrentLocationBanner> createState() => _CurrentLocationBannerState();
}

class _CurrentLocationBannerState extends State<CurrentLocationBanner> {
  final NearbyFriendsService _nearbyFriendsService = NearbyFriendsService();
  final BuildingService _buildingService = BuildingService();
  String? _buildingName;
  String? _previousBuildingName;
  bool _isFirstLoad = true;
  bool _isRefreshing = false;
  bool _isLocationEnabled = true;
  bool _locationCalculated = false;
  Timer? _timer;
  StreamSubscription<ServiceStatus>? _serviceStatusSubscription;

  @override
  void initState() {
    super.initState();
    _updateLocation();
    _timer = Timer.periodic(const Duration(minutes: 2), (_) => _updateLocation());
    _listenToLocationChanges();
  }

  void _listenToLocationChanges() {
    if (!kIsWeb) {
      _serviceStatusSubscription = Geolocator.getServiceStatusStream().listen((status) {
        debugPrint('DEBUG: [Banner] GPS Status changed to: $status');
        _updateLocation();
      });
    }
  }

  Future<void> _updateLocation() async {
    if (!mounted) return;
    debugPrint('DEBUG: [Banner] Starting location update for userId=${widget.userId}...');
    setState(() => _isRefreshing = true);

    final enabled = await LocationService.isLocationEnabled();
    debugPrint('DEBUG: [Banner] Location service enabled: $enabled');
    if (!enabled) {
      if (mounted) {
        setState(() {
          _isLocationEnabled = false;
          _locationCalculated = false;
          _buildingName = null;
          _isFirstLoad = false;
          _isRefreshing = false;
        });
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
        widget.userId,
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

      final buildingChanged = _previousBuildingName != newBuildingName;

      if (buildingChanged && newBuildingName != null && nearbyFriends.isNotEmpty) {
        debugPrint('DEBUG: [Banner] Building changed from "$_previousBuildingName" to "$newBuildingName" with ${nearbyFriends.length} friends nearby!');
        HapticFeedback.vibrate();
        if (mounted) {
          showDialog(
            context: context,
            builder: (_) => NearbyFriendsAlertDialog(
              buildingName: newBuildingName,
              friends: nearbyFriends,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _previousBuildingName = newBuildingName;
          _isLocationEnabled = true;
          _locationCalculated = true;
          _buildingName = newBuildingName;
          _isFirstLoad = false;
          _isRefreshing = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [Banner] Error updating location in banner: $e');
      debugPrint('$stackTrace');
      if (mounted) {
        setState(() {
          _isLocationEnabled = false;
          _locationCalculated = false;
          _isFirstLoad = false;
          _isRefreshing = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _serviceStatusSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    String text;
    IconData icon = Icons.location_on_rounded;
    Color iconColor = Colors.white.withValues(alpha: 0.5);

    if (_isFirstLoad) {
      text = 'Locating...';
    } else if (!_isLocationEnabled) {
      text = 'Location disabled';
      icon = Icons.location_off_rounded;
      iconColor = AppColors.accent1.withValues(alpha: 0.7);
    } else if (_locationCalculated) {
      if (_buildingName != null) {
        text = 'Current building: $_buildingName';
        iconColor = AppColors.accent2.withValues(alpha: 0.8);
      } else {
        text = 'Outside campus';
        iconColor = Colors.white.withValues(alpha: 0.5);
      }
    } else {
      text = 'Location unavailable';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Text(
          text,
          style: AppFonts.subtitle().copyWith(
            fontSize: 13,
            color: Colors.white.withValues(alpha: 0.5),
          ),
        ),
        if (_isRefreshing && !_isFirstLoad) ...[
          const SizedBox(width: 8),
          const SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white24),
            ),
          ),
        ],
      ],
    );
  }
}
