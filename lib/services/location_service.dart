import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Checks whether location services are enabled.
  static Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Requests permission to access the device location.
  static Future<LocationPermission> requestPermission() async {
    LocationPermission permission = await Geolocator.checkPermission();

    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission;
  }

  /// Gets the current device location.
  static Future<Position> getCurrentLocation() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (!serviceEnabled) {
      throw Exception(
        'Location services are disabled. Please enable location services.',
      );
    }

    final permission = await requestPermission();

    if (permission == LocationPermission.denied) {
      throw Exception(
        'Location permission was denied.',
      );
    }

    if (permission == LocationPermission.deniedForever) {
      throw Exception(
        'Location permission was permanently denied. '
        'Please enable it from your device settings.',
      );
    }

    return await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  /// Calculates the distance between the user's location
  /// and the event venue in metres.
  static double calculateDistance({
    required double userLatitude,
    required double userLongitude,
    required double eventLatitude,
    required double eventLongitude,
  }) {
    return Geolocator.distanceBetween(
      userLatitude,
      userLongitude,
      eventLatitude,
      eventLongitude,
    );
  }

  /// Checks whether the user is within the allowed
  /// check-in radius of the event venue.
  static bool isWithinCheckInRadius({
    required double distanceInMetres,
    double allowedRadius = 100,
  }) {
    return distanceInMetres <= allowedRadius;
  }
}