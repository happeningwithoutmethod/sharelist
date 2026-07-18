import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

const unknownCountryCode = 'unknown';

/// Resolves the host's ISO 3166-1 alpha-2 country code for play stats.
/// Returns [unknownCountryCode] when permission is denied or lookup fails.
Future<String> resolveHostCountryCode() async {
  if (kIsWeb) return unknownCountryCode;

  try {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return unknownCountryCode;

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return unknownCountryCode;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 8),
      ),
    );

    final placemarks = await placemarkFromCoordinates(
      position.latitude,
      position.longitude,
    );
    for (final place in placemarks) {
      final iso = place.isoCountryCode?.trim();
      if (iso != null && iso.isNotEmpty) {
        return iso.toUpperCase();
      }
    }
    return unknownCountryCode;
  } catch (_) {
    return unknownCountryCode;
  }
}
