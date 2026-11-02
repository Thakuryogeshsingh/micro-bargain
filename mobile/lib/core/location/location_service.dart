import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../config/app_config.dart';

class LatLng {
  const LatLng(this.latitude, this.longitude, {this.isFallback = false});

  final double latitude;
  final double longitude;

  /// True when we could not get the real position and used the city centre.
  final bool isFallback;
}

/// Current position, or Bharatpur centre if location is off or permission is denied.
Future<LatLng> currentLocation() async {
  const fallback = LatLng(AppConfig.fallbackLatitude, AppConfig.fallbackLongitude, isFallback: true);
  try {
    if (!await Geolocator.isLocationServiceEnabled()) return fallback;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) return fallback;
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: Duration(seconds: 10)),
    );
    return LatLng(position.latitude, position.longitude);
  } catch (_) {
    return fallback;
  }
}

final locationProvider = FutureProvider<LatLng>((ref) => currentLocation());
