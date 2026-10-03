import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Checks if location services are enabled and if permissions are granted.
  static Future<bool> isLocationEnabled() async {
    bool serviceEnabled;
    LocationPermission permission;

    // 1. Verificar si el sensor GPS está encendido
    serviceEnabled = await Geolocator.isLocationServiceEnabled();
    print('DEBUG: [LocationService] GPS Sensor Switch is: ${serviceEnabled ? "ON" : "OFF"}');
    if (!serviceEnabled) {
      return false;
    }

    // 2. Verificar permisos de la app
    permission = await Geolocator.checkPermission();
    print('DEBUG: [LocationService] App Permission is: $permission');

    if (permission == LocationPermission.denied || 
        permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  /// Requests location permission from the user.
  static Future<LocationPermission> requestPermission() async {
    return await Geolocator.requestPermission();
  }

  /// Opens the device settings for the app.
  static Future<void> openAppSettings() async {
    await Geolocator.openAppSettings();
  }

  /// Opens the location settings on the device.
  static Future<void> openLocationSettings() async {
    await Geolocator.openLocationSettings();
  }
}
