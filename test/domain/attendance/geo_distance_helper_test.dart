import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/attendance/geo_distance_helper.dart';

void main() {
  group('GeoDistanceHelper Tests', () {
    const storeLat = 10.035000;
    const storeLon = 105.788000;

    test('Identical coordinates return 0.0 distance', () {
      final distance = GeoDistanceHelper.haversineDistance(
        storeLat,
        storeLon,
        storeLat,
        storeLon,
      );
      expect(distance, 0.0);
    });

    test('Calculates accurate geodesic distance for nearby points (~77 meters)', () {
      // Small latitude offset: ~0.0007 degrees latitude is ~77.8 meters
      const staffLat = 10.035700;
      const staffLon = 105.788000;

      final distance = GeoDistanceHelper.haversineDistance(
        staffLat,
        staffLon,
        storeLat,
        storeLon,
      );

      expect(distance, greaterThan(75.0));
      expect(distance, lessThan(85.0));
    });

    test('isWithinRadius returns true when within 150m (e.g. ~78m)', () {
      const staffLat = 10.035700;
      const staffLon = 105.788000;

      final isValid = GeoDistanceHelper.isWithinRadius(
        staffLat: staffLat,
        staffLon: staffLon,
        storeLat: storeLat,
        storeLon: storeLon,
        allowedRadiusMeters: 150.0,
      );

      expect(isValid, isTrue);
    });

    test('isWithinRadius returns false when outside 150m (e.g. ~330m)', () {
      // ~0.003 degrees offset is ~330 meters
      const staffLat = 10.038000;
      const staffLon = 105.788000;

      final distance = GeoDistanceHelper.haversineDistance(
        staffLat,
        staffLon,
        storeLat,
        storeLon,
      );
      expect(distance, greaterThan(300.0));

      final isValid = GeoDistanceHelper.isWithinRadius(
        staffLat: staffLat,
        staffLon: staffLon,
        storeLat: storeLat,
        storeLon: storeLon,
        allowedRadiusMeters: 150.0,
      );

      expect(isValid, isFalse);
    });

    test('Custom allowed radius works correctly', () {
      const staffLat = 10.035700;
      const staffLon = 105.788000;
      // Distance is ~78m
      // If allowedRadius is 50m, should be false
      expect(
        GeoDistanceHelper.isWithinRadius(
          staffLat: staffLat,
          staffLon: staffLon,
          storeLat: storeLat,
          storeLon: storeLon,
          allowedRadiusMeters: 50.0,
        ),
        isFalse,
      );

      // If allowedRadius is 100m, should be true
      expect(
        GeoDistanceHelper.isWithinRadius(
          staffLat: staffLat,
          staffLon: staffLon,
          storeLat: storeLat,
          storeLon: storeLon,
          allowedRadiusMeters: 100.0,
        ),
        isTrue,
      );
    });
  });
}
