import 'geo_distance_helper.dart';

/// Domain entity representing a store's GPS location and allowed geofence radius.
class StoreGpsConfig {
  final String storeId;
  final double latitude;
  final double longitude;
  final double allowedRadiusMeters;
  final String? storeName;
  final String? address;
  final bool isActive;

  const StoreGpsConfig({
    required this.storeId,
    required this.latitude,
    required this.longitude,
    this.allowedRadiusMeters = GeoDistanceHelper.defaultAllowedRadiusMeters,
    this.storeName,
    this.address,
    this.isActive = true,
  });

  /// Check whether the given coordinates are within this store's allowed radius
  bool isWithinRadius(double staffLat, double staffLng) {
    return GeoDistanceHelper.isWithinRadius(
      staffLat: staffLat,
      staffLon: staffLng,
      storeLat: latitude,
      storeLon: longitude,
      allowedRadiusMeters: allowedRadiusMeters,
    );
  }

  /// Calculates geodesic distance to this store in meters
  double distanceTo(double staffLat, double staffLng) {
    return GeoDistanceHelper.haversineDistance(
      staffLat,
      staffLng,
      latitude,
      longitude,
    );
  }

  StoreGpsConfig copyWith({
    String? storeId,
    double? latitude,
    double? longitude,
    double? allowedRadiusMeters,
    String? storeName,
    String? address,
    bool? isActive,
  }) {
    return StoreGpsConfig(
      storeId: storeId ?? this.storeId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      allowedRadiusMeters: allowedRadiusMeters ?? this.allowedRadiusMeters,
      storeName: storeName ?? this.storeName,
      address: address ?? this.address,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoreGpsConfig &&
          runtimeType == other.runtimeType &&
          storeId == other.storeId &&
          latitude == other.latitude &&
          longitude == other.longitude &&
          allowedRadiusMeters == other.allowedRadiusMeters;

  @override
  int get hashCode =>
      storeId.hashCode ^
      latitude.hashCode ^
      longitude.hashCode ^
      allowedRadiusMeters.hashCode;
}
