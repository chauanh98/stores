import 'dart:async';

import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/domain/attendance/attendance_adjustment.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/attendance/attendance_repository.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/attendance/shift_repository.dart';
import 'package:stores/domain/attendance/store_gps_config.dart';

class FakeAttendanceRepository implements AttendanceRepository, ShiftRepository {
  List<Shift> shifts = Shift.defaultShifts();
  List<AttendanceRecord> attendances = [];
  List<AttendanceAdjustment> adjustments = [];
  Map<String, StoreGpsConfig> storeConfigs = {
    'store_001': const StoreGpsConfig(
      storeId: 'store_001',
      latitude: 10.035000,
      longitude: 105.788000,
      allowedRadiusMeters: 150.0,
      storeName: 'Chi nhánh Đông Thắng',
    ),
    'store_002': const StoreGpsConfig(
      storeId: 'store_002',
      latitude: 10.123000,
      longitude: 105.654000,
      allowedRadiusMeters: 150.0,
      storeName: 'Chi nhánh Thới Bình',
    ),
  };

  final StreamController<List<AttendanceRecord>> _attendanceController =
      StreamController<List<AttendanceRecord>>.broadcast();

  // ==========================================
  // SHIFT REPOSITORY
  // ==========================================

  @override
  Future<List<Shift>> getShifts() async => List.from(shifts);

  @override
  Future<Shift?> getShiftById(String id) async {
    try {
      return shifts.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveShift(Shift shift) async {
    final index = shifts.indexWhere((s) => s.id == shift.id);
    if (index >= 0) {
      shifts[index] = shift;
    } else {
      shifts.add(shift);
    }
  }

  @override
  Future<void> deleteShift(String id) async {
    shifts.removeWhere((s) => s.id == id);
  }

  @override
  Stream<List<Shift>> watchShifts() {
    return Stream.value(shifts);
  }

  // ==========================================
  // ATTENDANCE REPOSITORY
  // ==========================================

  @override
  Future<List<AttendanceRecord>> getAttendances({
    required String storeId,
    DateTime? date,
    String? userId,
  }) async {
    return attendances.where((r) {
      if (storeId.isNotEmpty && r.storeId != storeId) return false;
      if (date != null &&
          (r.date.year != date.year ||
              r.date.month != date.month ||
              r.date.day != date.day)) {
        return false;
      }
      if (userId != null && userId.isNotEmpty && r.userId != userId) return false;
      return true;
    }).toList();
  }

  @override
  Future<List<AttendanceRecord>> getMonthlyAttendances({
    required String storeId,
    required int year,
    required int month,
    String? userId,
  }) async {
    return attendances.where((r) {
      if (storeId.isNotEmpty && r.storeId != storeId) return false;
      if (r.date.year != year || r.date.month != month) return false;
      if (userId != null && userId.isNotEmpty && r.userId != userId) return false;
      return true;
    }).toList();
  }

  @override
  Future<AttendanceRecord?> getTodayAttendanceForUser({
    required String storeId,
    required String userId,
    required String shiftId,
    required DateTime date,
  }) async {
    for (final r in attendances) {
      if (r.storeId == storeId &&
          r.userId == userId &&
          r.shiftId == shiftId &&
          r.date.year == date.year &&
          r.date.month == date.month &&
          r.date.day == date.day) {
        return r;
      }
    }
    return null;
  }

  @override
  Future<void> saveAttendance(AttendanceRecord record) async {
    attendances.add(record);
    _attendanceController.add(attendances);
  }

  @override
  Future<void> updateAttendance(AttendanceRecord record) async {
    final index = attendances.indexWhere((r) => r.id == record.id);
    if (index >= 0) {
      attendances[index] = record;
      _attendanceController.add(attendances);
    }
  }

  @override
  Stream<List<AttendanceRecord>> watchTodayAttendances({
    required String storeId,
    required DateTime date,
  }) {
    return _attendanceController.stream.map((list) {
      return list.where((r) {
        return r.storeId == storeId &&
            r.date.year == date.year &&
            r.date.month == date.month &&
            r.date.day == date.day;
      }).toList();
    });
  }

  // ==========================================
  // ADJUSTMENTS
  // ==========================================

  @override
  Future<List<AttendanceAdjustment>> getAdjustments({
    String? storeId,
    String? userId,
    AdjustmentStatus? status,
  }) async {
    return adjustments.where((a) {
      if (storeId != null && storeId.isNotEmpty && a.storeId != storeId) return false;
      if (userId != null && userId.isNotEmpty && a.userId != userId) return false;
      if (status != null && a.status != status) return false;
      return true;
    }).toList();
  }

  @override
  Future<void> requestAdjustment(AttendanceAdjustment adjustment) async {
    adjustments.add(adjustment);
  }

  @override
  Future<void> reviewAdjustment({
    required String adjustmentId,
    required AdjustmentStatus status,
    required String reviewedBy,
    String? reviewNote,
  }) async {
    final index = adjustments.indexWhere((a) => a.id == adjustmentId);
    if (index >= 0) {
      final target = adjustments[index];
      final updated = target.copyWith(
        status: status,
        reviewedBy: reviewedBy,
        reviewedAt: DateTime.now(),
        reviewNote: reviewNote,
      );
      adjustments[index] = updated;

      if (status == AdjustmentStatus.approved && target.attendanceId.isNotEmpty) {
        final attIndex = attendances.indexWhere((a) => a.id == target.attendanceId);
        if (attIndex >= 0) {
          final att = attendances[attIndex];
          final workHours = AttendanceRecord.calculateWorkHours(
            target.requestedCheckIn,
            target.requestedCheckOut,
          );
          attendances[attIndex] = att.copyWith(
            checkInTime: target.requestedCheckIn,
            checkOutTime: target.requestedCheckOut,
            totalWorkHours: workHours,
            isAdjusted: true,
            adjustmentId: target.id,
            updatedAt: DateTime.now(),
          );
          _attendanceController.add(attendances);
        }
      }
    }
  }

  // ==========================================
  // STORE GPS CONFIG
  // ==========================================

  @override
  Future<StoreGpsConfig?> getStoreGpsConfig(String storeId) async {
    return storeConfigs[storeId];
  }

  @override
  Future<void> saveStoreGpsConfig(StoreGpsConfig config) async {
    storeConfigs[config.storeId] = config;
  }

  @override
  Stream<StoreGpsConfig?> watchStoreGpsConfig(String storeId) {
    return Stream.value(storeConfigs[storeId]);
  }
}

class FakeLocationService implements LocationService {
  GeoPoint? _position = const GeoPoint(10.035000, 105.788000, 'Tại cửa hàng');
  bool _isSimulated = false;

  @override
  bool get isSimulated => _isSimulated;

  @override
  void setSimulatedPosition(GeoPoint? point) {
    _position = point;
    _isSimulated = point != null;
  }

  @override
  Future<GeoPoint?> getCurrentPosition() async => _position;
}
