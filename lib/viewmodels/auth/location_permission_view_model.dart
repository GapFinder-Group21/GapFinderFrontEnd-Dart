import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gapfinderfrontend_dart/services/location_service.dart';

// What happened when the user tapped "Allow Location"
enum LocationPermissionResult { granted, deniedForever, denied }

// Asks the device for the location permission
class LocationPermissionViewModel extends ChangeNotifier {
  // Asks for the permission and tells the View the result
  Future<LocationPermissionResult> requestPermission() async {
    final permission = await LocationService.requestPermission();

    if (permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse) {
      return LocationPermissionResult.granted;
    }
    if (permission == LocationPermission.deniedForever) {
      return LocationPermissionResult.deniedForever;
    }
    return LocationPermissionResult.denied;
  }

  // Opens the app settings so the user can turn the permission on
  Future<void> openAppSettings() => LocationService.openAppSettings();
}
