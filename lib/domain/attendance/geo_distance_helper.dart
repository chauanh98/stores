import 'dart:math';

/// Pure Dart helper for calculating geodesic distances between coordinates
/// using the Haversine formula.
class GeoDistanceHelper {
  GeoDistanceHelper._();

  /// Mean radius of the Earth in meters.
  static const double earthRadiusMeters = 6371000.0;

  /// Default maximum allowed distance from store in meters.
  static const double defaultAllowedRadiusMeters = 150.0;

  /// Calculates the geodesic distance in meters between two GPS coordinate points
  /// (latitude and longitude in decimal degrees).
  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    if (lat1 == lat2 && lon1 == lon2) {
      return 0.0;
    }

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final radLat1 = _degreesToRadians(lat1);
    final radLat2 = _degreesToRadians(lat2);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(radLat1) * cos(radLat2) * sin(dLon / 2) * sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  /// Checks if the staff's coordinates are within the store's allowed radius.
  static bool isWithinRadius({
    required double staffLat,
    required double staffLon,
    required double storeLat,
    required double storeLon,
    double allowedRadiusMeters = defaultAllowedRadiusMeters,
  }) {
    final distance = haversineDistance(staffLat, staffLon, storeLat, storeLon);
    return distance <= allowedRadiusMeters;
  }

  static double _degreesToRadians(double degrees) {
    return degrees * pi / 180.0;
  }
}
