import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:gapfinderfrontend_dart/services/location_service.dart';
import 'package:gapfinderfrontend_dart/viewmodels/offline_aware_mixin.dart';

// What happened when the user tapped "Allow Location"
enum LocationPermissionResult { granted, deniedForever, denied }

// Asks the device for the location permission. The permission is a device setting, so it works
// without internet; the ViewModel only tells the View if there is a connection.
class LocationPermissionViewModel extends ChangeNotifier with OfflineAwareMixin {
  // Starts listening to the connection (nothing to reload when it comes back)
  void init() => listenToConnectivity(onRestored: () async {});

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
