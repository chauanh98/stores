import 'dart:async';
import 'package:firebase_database/firebase_database.dart';

import '../../../domain/attendance/geo_distance_helper.dart';
import '../../../domain/attendance/shift.dart';
import '../../models/attendance_adjustment_model.dart';
import '../../models/attendance_record_model.dart';
import '../../models/shift_model.dart';
import '../../models/store_gps_config_model.dart';

/// GPS coordinate point with optional description label.
class GeoPoint {
  final double latitude;
  final double longitude;
  final String? label;

  const GeoPoint(this.latitude, this.longitude, [this.label]);

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

/// Abstract location service supporting simulated and physical device coordinates.
abstract class LocationService {
  Future<GeoPoint?> getCurrentPosition();
  void setSimulatedPosition(GeoPoint? point);
  bool get isSimulated;
}

/// Default implementation of LocationService.
/// Supports setting simulated coordinates (e.g. at store or outside 150m for testing)
/// and falls back to default store coordinates.
class DefaultLocationService implements LocationService {
  GeoPoint? _simulatedPoint;

  @override
  bool get isSimulated => _simulatedPoint != null;

  @override
  void setSimulatedPosition(GeoPoint? point) {
    _simulatedPoint = point;
  }

  @override
  Future<GeoPoint?> getCurrentPosition() async {
    if (_simulatedPoint != null) {
      return _simulatedPoint;
    }
    // Default fallback coordinates (Chi nhánh Đông Thắng)
    return const GeoPoint(10.035000, 105.788000, 'Tọa độ GPS cửa hàng (Mặc định)');
  }
}

/// Remote data source communicating with Firebase Realtime Database for Attendance module.
class AttendanceRemoteDataSource {
  final FirebaseDatabase? _db;
  final LocationService _locationService;

  AttendanceRemoteDataSource({
    FirebaseDatabase? db,
    LocationService? locationService,
  })  : _db = db,
        _locationService = locationService ?? DefaultLocationService();

  LocationService get locationService => _locationService;

  DatabaseReference? get _shiftsRef => _db?.ref('shifts');
  DatabaseReference? get _attendancesRef => _db?.ref('attendances');
  DatabaseReference? get _adjustmentsRef => _db?.ref('attendance_adjustments');
  DatabaseReference _storeRef(String storeId) => _db!.ref('stores/$storeId');

  // ==========================================
  // SHIFTS
  // ==========================================

  Future<List<ShiftModel>> getShifts() async {
    final ref = _shiftsRef;
    if (ref == null) {
      return Shift.defaultShifts().map(ShiftModel.fromDomain).toList();
    }

    final snap = await ref.get();
    if (!snap.exists || snap.value == null) {
      // Seed default shifts
      final defaults = Shift.defaultShifts();
      for (final shift in defaults) {
        await ref.child(shift.id).set(ShiftModel.fromDomain(shift).toMap());
      }
      return defaults.map(ShiftModel.fromDomain).toList();
    }

    final List<ShiftModel> result = [];
    final data = snap.value;
    if (data is Map) {
      data.forEach((key, value) {
        if (value is Map) {
          result.add(ShiftModel.fromMap(Map<dynamic, dynamic>.from(value), id: key.toString()));
        }
      });
    } else if (data is List) {
      for (int i = 0; i < data.length; i++) {
        final item = data[i];
        if (item is Map) {
          result.add(ShiftModel.fromMap(Map<dynamic, dynamic>.from(item), id: 'shift_$i'));
        }
      }
    }

    if (result.isEmpty) {
      return Shift.defaultShifts().map(ShiftModel.fromDomain).toList();
    }
    return result;
  }

  Future<void> saveShift(ShiftModel shift) async {
    final ref = _shiftsRef;
    if (ref == null) return;
    await ref.child(shift.id).set(shift.toMap());
  }

  Future<void> deleteShift(String id) async {
    final ref = _shiftsRef;
    if (ref == null) return;
    await ref.child(id).remove();
  }

  Stream<List<ShiftModel>> watchShifts() {
    final ref = _shiftsRef;
    if (ref == null) {
      return Stream.value(Shift.defaultShifts().map(ShiftModel.fromDomain).toList());
    }

    return ref.onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        return Shift.defaultShifts().map(ShiftModel.fromDomain).toList();
      }
      final List<ShiftModel> result = [];
      final data = snap.value;
      if (data is Map) {
        data.forEach((key, value) {
          if (value is Map) {
            result.add(ShiftModel.fromMap(Map<dynamic, dynamic>.from(value), id: key.toString()));
          }
        });
      }
      return result.isEmpty ? Shift.defaultShifts().map(ShiftModel.fromDomain).toList() : result;
    });
  }

  // ==========================================
  // ATTENDANCES
  // ==========================================

  Future<List<AttendanceRecordModel>> getAttendances({
    required String storeId,
    String? dateStr, // YYYY-MM-DD
    String? userId,
  }) async {
    final ref = _attendancesRef;
    if (ref == null) return [];

    final snap = await ref.get();
    if (!snap.exists || snap.value == null) return [];

    final List<AttendanceRecordModel> list = [];
    final data = snap.value;
    if (data is Map) {
      data.forEach((key, val) {
        if (val is Map) {
          final model = AttendanceRecordModel.fromMap(Map<dynamic, dynamic>.from(val), id: key.toString());
          if (storeId.isNotEmpty && model.storeId != storeId) return;
          if (dateStr != null && model.date != dateStr) return;
          if (userId != null && userId.isNotEmpty && model.userId != userId) return;
          list.add(model);
        }
      });
    }
    return list;
  }

  Future<void> saveAttendance(AttendanceRecordModel record) async {
    final ref = _attendancesRef;
    if (ref == null) return;
    await ref.child(record.id).set(record.toMap());
  }

  Future<void> updateAttendance(AttendanceRecordModel record) async {
    final ref = _attendancesRef;
    if (ref == null) return;
    await ref.child(record.id).update(record.toMap());
  }

  Stream<List<AttendanceRecordModel>> watchAttendances({
    required String storeId,
    required String dateStr,
  }) {
    final ref = _attendancesRef;
    if (ref == null) return Stream.value([]);

    return ref.onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) return [];

      final List<AttendanceRecordModel> list = [];
      final data = snap.value;
      if (data is Map) {
        data.forEach((key, val) {
          if (val is Map) {
            final model = AttendanceRecordModel.fromMap(Map<dynamic, dynamic>.from(val), id: key.toString());
            if (storeId.isNotEmpty && model.storeId != storeId) return;
            if (model.date != dateStr) return;
            list.add(model);
          }
        });
      }
      return list;
    });
  }

  // ==========================================
  // ADJUSTMENTS
  // ==========================================

  Future<List<AttendanceAdjustmentModel>> getAdjustments({
    String? storeId,
    String? userId,
    String? status,
  }) async {
    final ref = _adjustmentsRef;
    if (ref == null) return [];

    final snap = await ref.get();
    if (!snap.exists || snap.value == null) return [];

    final List<AttendanceAdjustmentModel> list = [];
    final data = snap.value;
    if (data is Map) {
      data.forEach((key, val) {
        if (val is Map) {
          final model = AttendanceAdjustmentModel.fromMap(Map<dynamic, dynamic>.from(val), id: key.toString());
          if (storeId != null && storeId.isNotEmpty && model.storeId != storeId) return;
          if (userId != null && userId.isNotEmpty && model.userId != userId) return;
          if (status != null && status.isNotEmpty && model.status != status) return;
          list.add(model);
        }
      });
    }
    return list;
  }

  Future<void> saveAdjustment(AttendanceAdjustmentModel adjustment) async {
    final ref = _adjustmentsRef;
    if (ref == null) return;
    await ref.child(adjustment.id).set(adjustment.toMap());
  }

  Future<void> updateAdjustment(AttendanceAdjustmentModel adjustment) async {
    final ref = _adjustmentsRef;
    if (ref == null) return;
    await ref.child(adjustment.id).update(adjustment.toMap());
  }

  Stream<List<AttendanceAdjustmentModel>> watchAdjustments({String? storeId}) {
    final ref = _adjustmentsRef;
    if (ref == null) return Stream.value([]);

    return ref.onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) return [];

      final List<AttendanceAdjustmentModel> list = [];
      final data = snap.value;
      if (data is Map) {
        data.forEach((key, val) {
          if (val is Map) {
            final model = AttendanceAdjustmentModel.fromMap(Map<dynamic, dynamic>.from(val), id: key.toString());
            if (storeId != null && storeId.isNotEmpty && model.storeId != storeId) return;
            list.add(model);
          }
        });
      }
      return list;
    });
  }

  // ==========================================
  // STORE GPS CONFIG
  // ==========================================

  Future<StoreGpsConfigModel?> getStoreGpsConfig(String storeId) async {
    if (_db == null) {
      return StoreGpsConfigModel(
        storeId: storeId,
        latitude: 10.035000,
        longitude: 105.788000,
        allowedRadiusMeters: GeoDistanceHelper.defaultAllowedRadiusMeters,
      );
    }

    final ref = _storeRef(storeId);
    final snap = await ref.get();
    if (!snap.exists || snap.value == null) {
      return StoreGpsConfigModel(
        storeId: storeId,
        latitude: 10.035000,
        longitude: 105.788000,
        allowedRadiusMeters: GeoDistanceHelper.defaultAllowedRadiusMeters,
      );
    }

    final data = snap.value;
    if (data is Map) {
      return StoreGpsConfigModel.fromMap(Map<dynamic, dynamic>.from(data), storeId: storeId);
    }
    return null;
  }

  Future<void> saveStoreGpsConfig(StoreGpsConfigModel config) async {
    if (_db == null) return;
    final ref = _storeRef(config.storeId);
    await ref.update({
      'latitude': config.latitude,
      'longitude': config.longitude,
      'allowedRadiusMeters': config.allowedRadiusMeters,
      if (config.storeName != null) 'name': config.storeName,
      if (config.address != null) 'address': config.address,
    });
  }

  Stream<StoreGpsConfigModel?> watchStoreGpsConfig(String storeId) {
    if (_db == null) {
      return Stream.value(
        StoreGpsConfigModel(
          storeId: storeId,
          latitude: 10.035000,
          longitude: 105.788000,
          allowedRadiusMeters: GeoDistanceHelper.defaultAllowedRadiusMeters,
        ),
      );
    }

    return _storeRef(storeId).onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists || snap.value == null) {
        return StoreGpsConfigModel(
          storeId: storeId,
          latitude: 10.035000,
          longitude: 105.788000,
          allowedRadiusMeters: GeoDistanceHelper.defaultAllowedRadiusMeters,
        );
      }
      final data = snap.value;
      if (data is Map) {
        return StoreGpsConfigModel.fromMap(Map<dynamic, dynamic>.from(data), storeId: storeId);
      }
      return null;
    });
  }
}
