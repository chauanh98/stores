import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/attendance/geo_distance_helper.dart';

void main() {
  group('Haversine & Geofence Boundary Adversarial Tests', () {
    const storeLat = 10.035000;
    const storeLon = 105.788000;
    const earthRadius = GeoDistanceHelper.earthRadiusMeters;

    test('Zero coordinates: distance between (0, 0) and (0, 0) is 0.0m', () {
      final d = GeoDistanceHelper.haversineDistance(0.0, 0.0, 0.0, 0.0);
      expect(d, 0.0);
      expect(
        GeoDistanceHelper.isWithinRadius(
          staffLat: 0.0,
          staffLon: 0.0,
          storeLat: 0.0,
          storeLon: 0.0,
          allowedRadiusMeters: 150.0,
        ),
        isTrue,
      );
    });

    test(
        'Zero coordinates: 1 degree longitude at equator equals theoretical distance',
        () {
      final d = GeoDistanceHelper.haversineDistance(0.0, 0.0, 0.0, 1.0);
      const theoretical = earthRadius * (pi / 180.0);
      expect((d - theoretical).abs(), lessThan(1e-4));
      expect(d, closeTo(111194.9, 0.1));
    });

    test('Exact boundary test: 150.0m is valid (isWithinRadius == true)', () {
      // 150m along latitude
      const deltaLatDeg = (150.0 / earthRadius) * (180.0 / pi);
      const staffLat = storeLat + deltaLatDeg;
      const staffLon = storeLon;

      final distance = GeoDistanceHelper.haversineDistance(
        staffLat,
        staffLon,
        storeLat,
        storeLon,
      );
      expect(distance, closeTo(150.0, 1e-6));

      final isWithin = GeoDistanceHelper.isWithinRadius(
        staffLat: staffLat,
        staffLon: staffLon,
        storeLat: storeLat,
        storeLon: storeLon,
        allowedRadiusMeters: 150.0,
      );
      expect(isWithin, isTrue,
          reason:
              'Distance of exactly 150.0m must be within 150.0m radius (<= 150.0)');
    });

    test('Just inside boundary test: 149.9m is valid (isWithinRadius == true)',
        () {
      const deltaLatDeg = (149.9 / earthRadius) * (180.0 / pi);
      const staffLat = storeLat + deltaLatDeg;
      const staffLon = storeLon;

      final distance = GeoDistanceHelper.haversineDistance(
        staffLat,
        staffLon,
        storeLat,
        storeLon,
      );
      expect(distance, closeTo(149.9, 1e-6));
      expect(distance, lessThan(150.0));

      final isWithin = GeoDistanceHelper.isWithinRadius(
        staffLat: staffLat,
        staffLon: staffLon,
        storeLat: storeLat,
        storeLon: storeLon,
        allowedRadiusMeters: 150.0,
      );
      expect(isWithin, isTrue);
    });

    test(
        'Just outside boundary test: 150.1m is invalid (isWithinRadius == false)',
        () {
      const deltaLatDeg = (150.1 / earthRadius) * (180.0 / pi);
      const staffLat = storeLat + deltaLatDeg;
      const staffLon = storeLon;

      final distance = GeoDistanceHelper.haversineDistance(
        staffLat,
        staffLon,
        storeLat,
        storeLon,
      );
      expect(distance, closeTo(150.1, 1e-6));
      expect(distance, greaterThan(150.0));

      final isWithin = GeoDistanceHelper.isWithinRadius(
        staffLat: staffLat,
        staffLon: staffLon,
        storeLat: storeLat,
        storeLon: storeLon,
        allowedRadiusMeters: 150.0,
      );
      expect(isWithin, isFalse);
    });

    test('Antipode coordinates: (0,0) and (0,180) equals pi * R without NaN',
        () {
      final d = GeoDistanceHelper.haversineDistance(0.0, 0.0, 0.0, 180.0);
      expect(d.isNaN, isFalse);
      expect(d, closeTo(pi * earthRadius, 0.1));
    });

    test(
        'Antipode coordinates across various latitudes (-45, 10) vs (45, -170)',
        () {
      final d = GeoDistanceHelper.haversineDistance(-45.0, 10.0, 45.0, -170.0);
      expect(d.isNaN, isFalse);
      expect(d, closeTo(pi * earthRadius, 1.0));
    });

    test('Extreme latitudes: North Pole (90, 0) to South Pole (-90, 0)', () {
      final d = GeoDistanceHelper.haversineDistance(90.0, 0.0, -90.0, 0.0);
      expect(d.isNaN, isFalse);
      expect(d, closeTo(pi * earthRadius, 0.1));
    });

    test(
        'Extreme latitudes: North Pole at different longitudes represents same point (~0m)',
        () {
      final d = GeoDistanceHelper.haversineDistance(90.0, 0.0, 90.0, 120.0);
      expect(d.isNaN, isFalse);
      expect(d, lessThan(1e-3)); // Within 1 millimeter
    });

    test('Floating point resilience test across 360 degree polar sweeps', () {
      for (int lon = -180; lon <= 180; lon += 45) {
        final d = GeoDistanceHelper.haversineDistance(89.999999, lon.toDouble(),
            -89.999999, (lon > 0 ? lon - 180 : lon + 180).toDouble());
        expect(d.isNaN, isFalse,
            reason: 'Haversine must not produce NaN for lon $lon');
        expect(d, greaterThan(19000000.0));
      }
    });
  });
}
