import '../../domain/attendance/geo_distance_helper.dart';
import '../../domain/attendance/store_gps_config.dart';

class StoreGpsConfigModel {
  final String storeId;
  final double latitude;
  final double longitude;
  final double allowedRadiusMeters;
  final String? storeName;
  final String? address;
  final bool isActive;

  const StoreGpsConfigModel({
    required this.storeId,
    required this.latitude,
    required this.longitude,
    this.allowedRadiusMeters = GeoDistanceHelper.defaultAllowedRadiusMeters,
    this.storeName,
    this.address,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'storeId': storeId,
      'latitude': latitude,
      'longitude': longitude,
      'allowedRadiusMeters': allowedRadiusMeters,
      if (storeName != null) 'name': storeName,
      if (address != null) 'address': address,
      'isActive': isActive,
    };
  }

  factory StoreGpsConfigModel.fromMap(Map<dynamic, dynamic> map, {String? storeId}) {
    return StoreGpsConfigModel(
      storeId: storeId ?? map['storeId']?.toString() ?? '',
      latitude: (map['latitude'] as num?)?.toDouble() ?? 10.035,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 105.788,
      allowedRadiusMeters: (map['allowedRadiusMeters'] as num?)?.toDouble() ??
          GeoDistanceHelper.defaultAllowedRadiusMeters,
      storeName: map['name']?.toString() ?? map['storeName']?.toString(),
      address: map['address']?.toString(),
      isActive: map['isActive'] == null ? true : (map['isActive'] as bool),
    );
  }

  StoreGpsConfig toDomain() {
    return StoreGpsConfig(
      storeId: storeId,
      latitude: latitude,
      longitude: longitude,
      allowedRadiusMeters: allowedRadiusMeters,
      storeName: storeName,
      address: address,
      isActive: isActive,
    );
  }

  factory StoreGpsConfigModel.fromDomain(StoreGpsConfig config) {
    return StoreGpsConfigModel(
      storeId: config.storeId,
      latitude: config.latitude,
      longitude: config.longitude,
      allowedRadiusMeters: config.allowedRadiusMeters,
      storeName: config.storeName,
      address: config.address,
      isActive: config.isActive,
    );
  }
}
