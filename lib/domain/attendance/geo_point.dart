/// Pure domain representation of a GPS coordinate point with optional description label.
class GeoPoint {
  final double latitude;
  final double longitude;
  final String? label;

  const GeoPoint(this.latitude, this.longitude, [this.label]);

  const GeoPoint.named({
    required this.latitude,
    required this.longitude,
    this.label,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint &&
          runtimeType == other.runtimeType &&
          latitude == other.latitude &&
          longitude == other.longitude;

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}
