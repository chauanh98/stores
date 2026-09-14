import 'attendance_adjustment.dart';
import 'attendance_record.dart';
import 'store_gps_config.dart';

/// Repository interface for staff attendance records, adjustments, and store GPS configuration.
abstract class AttendanceRepository {
  /// Fetches attendance records filtered by store, optional date and optional userId.
  Future<List<AttendanceRecord>> getAttendances({
    required String storeId,
    DateTime? date,
    String? userId,
  });

  /// Fetches attendance records for a specific month and year, optionally filtered by user.
  Future<List<AttendanceRecord>> getMonthlyAttendances({
    required String storeId,
    required int year,
    required int month,
    String? userId,
  });

  /// Fetches the user's attendance record for a specific shift and date (to check if already checked in).
  Future<AttendanceRecord?> getTodayAttendanceForUser({
    required String storeId,
    required String userId,
    required String shiftId,
    required DateTime date,
  });

  /// Saves a new attendance check-in record.
  Future<void> saveAttendance(AttendanceRecord record);

  /// Updates an existing attendance record (e.g. check-out, adjustment).
  Future<void> updateAttendance(AttendanceRecord record);

  /// Streams today's attendance records in real time for live dashboard monitoring.
  Stream<List<AttendanceRecord>> watchTodayAttendances({
    required String storeId,
    required DateTime date,
  });

  // ==========================================
  // ATTENDANCE ADJUSTMENTS
  // ==========================================

  /// Fetches adjustment requests filtered by store, user, or status.
  Future<List<AttendanceAdjustment>> getAdjustments({
    String? storeId,
    String? userId,
    AdjustmentStatus? status,
  });

  /// Submits a new adjustment request from staff.
  Future<void> requestAdjustment(AttendanceAdjustment adjustment);

  /// Reviews (approves or rejects) an adjustment request.
  Future<void> reviewAdjustment({
    required String adjustmentId,
    required AdjustmentStatus status,
    required String reviewedBy,
    String? reviewNote,
  });

  // ==========================================
  // STORE GPS CONFIGURATION
  // ==========================================

  /// Gets the GPS configuration (lat, lng, radius) for a specific store.
  Future<StoreGpsConfig?> getStoreGpsConfig(String storeId);

  /// Saves or updates the GPS configuration for a store.
  Future<void> saveStoreGpsConfig(StoreGpsConfig config);

  /// Streams the GPS configuration for a store.
  Stream<StoreGpsConfig?> watchStoreGpsConfig(String storeId);
}
