import 'dart:async';

import '../../domain/attendance/attendance_adjustment.dart';
import '../../domain/attendance/attendance_record.dart';
import '../../domain/attendance/attendance_repository.dart';
import '../../domain/attendance/shift.dart';
import '../../domain/attendance/shift_repository.dart';
import '../../domain/attendance/store_gps_config.dart';
import '../datasources/firebase/attendance_remote_data_source.dart';
import '../models/attendance_adjustment_model.dart';
import '../models/attendance_record_model.dart';
import '../models/shift_model.dart';
import '../models/store_gps_config_model.dart';

/// Repository implementation for ShiftRepository and AttendanceRepository.
class AttendanceRepositoryImpl
    implements AttendanceRepository, ShiftRepository {
  final AttendanceRemoteDataSource _dataSource;

  AttendanceRepositoryImpl(this._dataSource);

  // ==========================================
  // SHIFT REPOSITORY IMPLEMENTATION
  // ==========================================

  @override
  Future<List<Shift>> getShifts() async {
    final models = await _dataSource.getShifts();
    return models.map((m) => m.toDomain()).toList();
  }

  @override
  Future<Shift?> getShiftById(String id) async {
    final shifts = await getShifts();
    try {
      return shifts.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> saveShift(Shift shift) async {
    final model = ShiftModel.fromDomain(shift);
    await _dataSource.saveShift(model);
  }

  @override
  Future<void> deleteShift(String id) async {
    await _dataSource.deleteShift(id);
  }

  @override
  Stream<List<Shift>> watchShifts() {
    return _dataSource.watchShifts().map(
          (models) => models.map((m) => m.toDomain()).toList(),
        );
  }

  // ==========================================
  // ATTENDANCE REPOSITORY IMPLEMENTATION
  // ==========================================

  String _formatDate(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  @override
  Future<List<AttendanceRecord>> getAttendances({
    required String storeId,
    DateTime? date,
    String? userId,
  }) async {
    final dateStr = date != null ? _formatDate(date) : null;
    final models = await _dataSource.getAttendances(
      storeId: storeId,
      dateStr: dateStr,
      userId: userId,
    );
    return models.map((m) => m.toDomain()).toList();
  }

  @override
  Future<List<AttendanceRecord>> getMonthlyAttendances({
    required String storeId,
    required int year,
    required int month,
    String? userId,
  }) async {
    final prefix =
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
    final models = await _dataSource.getAttendances(
      storeId: storeId,
      userId: userId,
    );
    return models
        .where((m) => m.date.startsWith(prefix))
        .map((m) => m.toDomain())
        .toList();
  }

  @override
  Future<AttendanceRecord?> getTodayAttendanceForUser({
    required String storeId,
    required String userId,
    required String shiftId,
    required DateTime date,
  }) async {
    final dateStr = _formatDate(date);
    final models = await _dataSource.getAttendances(
      storeId: storeId,
      dateStr: dateStr,
      userId: userId,
    );
    for (final m in models) {
      if (m.shiftId == shiftId) {
        return m.toDomain();
      }
    }
    return null;
  }

  @override
  Future<void> saveAttendance(AttendanceRecord record) async {
    final model = AttendanceRecordModel.fromDomain(record);
    await _dataSource.saveAttendance(model);
  }

  @override
  Future<void> updateAttendance(AttendanceRecord record) async {
    final model = AttendanceRecordModel.fromDomain(record);
    await _dataSource.updateAttendance(model);
  }

  @override
  Stream<List<AttendanceRecord>> watchTodayAttendances({
    required String storeId,
    required DateTime date,
  }) {
    final dateStr = _formatDate(date);
    return _dataSource
        .watchAttendances(storeId: storeId, dateStr: dateStr)
        .map((models) => models.map((m) => m.toDomain()).toList());
  }

  // ==========================================
  // ATTENDANCE ADJUSTMENTS
  // ==========================================

  @override
  Future<List<AttendanceAdjustment>> getAdjustments({
    String? storeId,
    String? userId,
    AdjustmentStatus? status,
  }) async {
    final models = await _dataSource.getAdjustments(
      storeId: storeId,
      userId: userId,
      status: status?.value,
    );
    return models.map((m) => m.toDomain()).toList();
  }

  @override
  Future<void> requestAdjustment(AttendanceAdjustment adjustment) async {
    final model = AttendanceAdjustmentModel.fromDomain(adjustment);
    await _dataSource.saveAdjustment(model);
  }

  @override
  Future<void> reviewAdjustment({
    required String adjustmentId,
    required AdjustmentStatus status,
    required String reviewedBy,
    String? reviewNote,
  }) async {
    final adjustments = await _dataSource.getAdjustments();
    final target = adjustments.firstWhere(
      (a) => a.id == adjustmentId,
      orElse: () => throw Exception('Adjustment not found: $adjustmentId'),
    );

    final updated = AttendanceAdjustmentModel(
      id: target.id,
      attendanceId: target.attendanceId,
      userId: target.userId,
      userName: target.userName,
      storeId: target.storeId,
      requestedCheckIn: target.requestedCheckIn,
      requestedCheckOut: target.requestedCheckOut,
      reason: target.reason,
      status: status.value,
      reviewedBy: reviewedBy,
      reviewedAt: DateTime.now().toIso8601String(),
      reviewNote: reviewNote,
      submittedAt: target.submittedAt,
    );

    await _dataSource.updateAdjustment(updated);

    // If approved, update the corresponding attendance record
    if (status == AdjustmentStatus.approved && target.attendanceId.isNotEmpty) {
      final attendances =
          await _dataSource.getAttendances(storeId: target.storeId);
      for (final att in attendances) {
        if (att.id == target.attendanceId) {
          final domainAtt = att.toDomain();
          final parsedIn = DateTime.parse(target.requestedCheckIn);
          final parsedOut = DateTime.parse(target.requestedCheckOut);
          final workHours =
              AttendanceRecord.calculateWorkHours(parsedIn, parsedOut);

          final adjustedRecord = domainAtt.copyWith(
            checkInTime: parsedIn,
            checkOutTime: parsedOut,
            totalWorkHours: workHours,
            isAdjusted: true,
            adjustmentId: target.id,
            updatedAt: DateTime.now(),
          );
          await _dataSource.updateAttendance(
              AttendanceRecordModel.fromDomain(adjustedRecord));
          break;
        }
      }
    }
  }

  // ==========================================
  // STORE GPS CONFIGURATION
  // ==========================================

  @override
  Future<StoreGpsConfig?> getStoreGpsConfig(String storeId) async {
    final model = await _dataSource.getStoreGpsConfig(storeId);
    return model?.toDomain();
  }

  @override
  Future<void> saveStoreGpsConfig(StoreGpsConfig config) async {
    final model = StoreGpsConfigModel.fromDomain(config);
    await _dataSource.saveStoreGpsConfig(model);
  }

  @override
  Stream<StoreGpsConfig?> watchStoreGpsConfig(String storeId) {
    return _dataSource.watchStoreGpsConfig(storeId).map((m) => m?.toDomain());
  }
}
