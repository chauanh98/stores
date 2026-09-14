import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/attendance_remote_data_source.dart';
import '../../domain/attendance/attendance_record.dart';
import '../../domain/attendance/attendance_repository.dart';
import '../../domain/attendance/geo_distance_helper.dart';
import '../../domain/attendance/shift.dart';
import '../../domain/attendance/store_gps_config.dart';
import '../../domain/entities/user_account.dart';
import 'attendance_providers.dart';

class AttendanceCheckInState {
  final Shift? selectedShift;
  final GeoPoint? currentPosition;
  final double distanceToStoreMeters;
  final bool isWithinRadius;
  final StoreGpsConfig? storeGpsConfig;
  final AttendanceRecord? todayAttendance;
  final bool isLoading;
  final bool isCheckingInOut;
  final String? errorMessage;
  final String? successMessage;

  const AttendanceCheckInState({
    this.selectedShift,
    this.currentPosition,
    this.distanceToStoreMeters = 0.0,
    this.isWithinRadius = true,
    this.storeGpsConfig,
    this.todayAttendance,
    this.isLoading = false,
    this.isCheckingInOut = false,
    this.errorMessage,
    this.successMessage,
  });

  bool get canCheckIn =>
      todayAttendance == null && !isCheckingInOut;

  bool get canCheckOut =>
      todayAttendance != null &&
      todayAttendance!.checkOutTime == null &&
      !isCheckingInOut;

  bool get isCompletedToday =>
      todayAttendance != null && todayAttendance!.checkOutTime != null;

  AttendanceCheckInState copyWith({
    Shift? selectedShift,
    GeoPoint? currentPosition,
    double? distanceToStoreMeters,
    bool? isWithinRadius,
    StoreGpsConfig? storeGpsConfig,
    AttendanceRecord? todayAttendance,
    bool? isLoading,
    bool? isCheckingInOut,
    String? errorMessage,
    String? successMessage,
    bool clearTodayAttendance = false,
  }) {
    return AttendanceCheckInState(
      selectedShift: selectedShift ?? this.selectedShift,
      currentPosition: currentPosition ?? this.currentPosition,
      distanceToStoreMeters: distanceToStoreMeters ?? this.distanceToStoreMeters,
      isWithinRadius: isWithinRadius ?? this.isWithinRadius,
      storeGpsConfig: storeGpsConfig ?? this.storeGpsConfig,
      todayAttendance: clearTodayAttendance
          ? null
          : (todayAttendance ?? this.todayAttendance),
      isLoading: isLoading ?? this.isLoading,
      isCheckingInOut: isCheckingInOut ?? this.isCheckingInOut,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class AttendanceNotifier extends StateNotifier<AttendanceCheckInState> {
  final AttendanceRepository _attendanceRepository;
  final LocationService _locationService;

  AttendanceNotifier(
    this._attendanceRepository,
    this._locationService,
  ) : super(const AttendanceCheckInState());

  /// Initializes GPS location, store GPS configuration, and checks existing attendance.
  Future<void> init({
    required String storeId,
    required String userId,
    Shift? initialShift,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final config = await _attendanceRepository.getStoreGpsConfig(storeId) ??
          StoreGpsConfig(
            storeId: storeId,
            latitude: 10.035000,
            longitude: 105.788000,
            allowedRadiusMeters: GeoDistanceHelper.defaultAllowedRadiusMeters,
          );

      final position = await _locationService.getCurrentPosition();
      final lat = position?.latitude ?? config.latitude;
      final lng = position?.longitude ?? config.longitude;

      final distance = GeoDistanceHelper.haversineDistance(
        lat,
        lng,
        config.latitude,
        config.longitude,
      );

      final isWithin = distance <= config.allowedRadiusMeters;

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      AttendanceRecord? existingAttendance;
      if (initialShift != null) {
        existingAttendance =
            await _attendanceRepository.getTodayAttendanceForUser(
          storeId: storeId,
          userId: userId,
          shiftId: initialShift.id,
          date: today,
        );
      }

      state = state.copyWith(
        selectedShift: initialShift ?? state.selectedShift,
        currentPosition: position,
        distanceToStoreMeters: distance,
        isWithinRadius: isWithin,
        storeGpsConfig: config,
        todayAttendance: existingAttendance,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi khởi tạo chấm công: $e',
      );
    }
  }

  /// Sets or switches the selected shift.
  Future<void> selectShift(
    Shift shift, {
    required String storeId,
    required String userId,
  }) async {
    state = state.copyWith(
      selectedShift: shift,
      clearTodayAttendance: true,
      isLoading: true,
      errorMessage: null,
    );

    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final existingAttendance =
          await _attendanceRepository.getTodayAttendanceForUser(
        storeId: storeId,
        userId: userId,
        shiftId: shift.id,
        date: today,
      );

      state = state.copyWith(
        todayAttendance: existingAttendance,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải trạng thái ca: $e',
      );
    }
  }

  /// Refreshes current GPS position and updates distance calculations.
  Future<void> refreshLocation({required String storeId}) async {
    try {
      final position = await _locationService.getCurrentPosition();
      final config = state.storeGpsConfig ??
          await _attendanceRepository.getStoreGpsConfig(storeId) ??
          StoreGpsConfig(
            storeId: storeId,
            latitude: 10.035000,
            longitude: 105.788000,
          );

      final lat = position?.latitude ?? config.latitude;
      final lng = position?.longitude ?? config.longitude;

      final distance = GeoDistanceHelper.haversineDistance(
        lat,
        lng,
        config.latitude,
        config.longitude,
      );
      final isWithin = distance <= config.allowedRadiusMeters;

      state = state.copyWith(
        currentPosition: position,
        distanceToStoreMeters: distance,
        isWithinRadius: isWithin,
        storeGpsConfig: config,
      );
    } catch (e) {
      state = state.copyWith(errorMessage: 'Lỗi định vị GPS: $e');
    }
  }

  /// Sets simulated position for testing/demo coordinates.
  void setSimulatedCoordinates(GeoPoint point, {required String storeId}) {
    _locationService.setSimulatedPosition(point);
    refreshLocation(storeId: storeId);
  }

  /// Performs Check-in ("Chấm công Vào").
  Future<bool> checkIn({
    required UserAccount user,
    required String storeId,
    String? explanationReason,
    DateTime? checkInTimestamp,
  }) async {
    if (!user.requiresAttendance) {
      state = state.copyWith(
        isCheckingInOut: false,
        errorMessage: 'Tài khoản quản lý không thuộc đối tượng chấm công.',
      );
      return false;
    }

    final shift = state.selectedShift;
    if (shift == null) {
      state = state.copyWith(errorMessage: 'Vui lòng chọn ca làm việc.');
      return false;
    }

    if (state.todayAttendance != null) {
      state = state.copyWith(errorMessage: 'Bạn đã chấm công vào ca này hôm nay.');
      return false;
    }

    state = state.copyWith(isCheckingInOut: true, errorMessage: null, successMessage: null);

    try {
      final now = checkInTimestamp ?? DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // Verify GPS distance
      final config = state.storeGpsConfig ??
          await _attendanceRepository.getStoreGpsConfig(storeId) ??
          StoreGpsConfig(
            storeId: storeId,
            latitude: 10.035000,
            longitude: 105.788000,
          );

      final pos = state.currentPosition ?? await _locationService.getCurrentPosition();
      final lat = pos?.latitude ?? config.latitude;
      final lng = pos?.longitude ?? config.longitude;

      final distance = GeoDistanceHelper.haversineDistance(
        lat,
        lng,
        config.latitude,
        config.longitude,
      );

      final isGpsValid = distance <= config.allowedRadiusMeters;

      if (!isGpsValid && (explanationReason == null || explanationReason.trim().isEmpty)) {
        state = state.copyWith(
          isCheckingInOut: false,
          errorMessage:
              'Bạn đang ở ngoài bán kính (${distance.toStringAsFixed(1)}m > ${config.allowedRadiusMeters}m). Vui lòng nhập lý do giải trình để tiếp tục.',
        );
        return false;
      }

      // Compute late minutes
      final lateMinutes = shift.calculateLateMinutes(now, today);
      final status = lateMinutes > 0 ? AttendanceStatus.late : AttendanceStatus.onTime;

      final dateKey = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
      final recordId = 'att_${storeId}_${user.username}_${shift.id}_$dateKey';

      final record = AttendanceRecord(
        id: recordId,
        userId: user.username,
        userName: user.name,
        storeId: storeId,
        shiftId: shift.id,
        shiftName: shift.name,
        date: today,
        checkInTime: now,
        status: status,
        lateMinutes: lateMinutes,
        checkInGpsLat: lat,
        checkInGpsLng: lng,
        isGpsValid: isGpsValid,
        explanationReason: explanationReason?.trim().isNotEmpty == true ? explanationReason?.trim() : null,
        createdAt: now,
        updatedAt: now,
      );

      await _attendanceRepository.saveAttendance(record);

      state = state.copyWith(
        todayAttendance: record,
        isCheckingInOut: false,
        successMessage: isGpsValid
            ? 'Chấm công Vào thành công! (${status.label})'
            : 'Chấm công Vào thành công kèm lý do giải trình!',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isCheckingInOut: false,
        errorMessage: 'Lỗi khi chấm công Vào: $e',
      );
      return false;
    }
  }

  /// Performs Check-out ("Chấm công Ra").
  Future<bool> checkOut({
    required UserAccount user,
    required String storeId,
    String? explanationReason,
    DateTime? checkOutTimestamp,
  }) async {
    if (!user.requiresAttendance) {
      state = state.copyWith(
        isCheckingInOut: false,
        errorMessage: 'Tài khoản quản lý không thuộc đối tượng chấm công.',
      );
      return false;
    }

    final record = state.todayAttendance;
    if (record == null) {
      state = state.copyWith(errorMessage: 'Không tìm thấy bản ghi vào ca để chấm công ra.');
      return false;
    }

    if (record.checkOutTime != null) {
      state = state.copyWith(errorMessage: 'Bạn đã hoàn tất chấm công ra ca này rồi.');
      return false;
    }

    final shift = state.selectedShift;
    if (shift == null) {
      state = state.copyWith(errorMessage: 'Không tìm thấy thông tin ca làm việc.');
      return false;
    }

    state = state.copyWith(isCheckingInOut: true, errorMessage: null, successMessage: null);

    try {
      final now = checkOutTimestamp ?? DateTime.now();
      final today = record.date;

      final config = state.storeGpsConfig ??
          await _attendanceRepository.getStoreGpsConfig(storeId) ??
          StoreGpsConfig(
            storeId: storeId,
            latitude: 10.035000,
            longitude: 105.788000,
          );

      final pos = state.currentPosition ?? await _locationService.getCurrentPosition();
      final lat = pos?.latitude ?? config.latitude;
      final lng = pos?.longitude ?? config.longitude;

      final distance = GeoDistanceHelper.haversineDistance(
        lat,
        lng,
        config.latitude,
        config.longitude,
      );

      final isCheckOutGpsValid = distance <= config.allowedRadiusMeters;

      // Status calculations
      final earlyLeaveMinutes = shift.calculateEarlyLeaveMinutes(now, today);
      final overtimeMinutes = shift.calculateOvertimeMinutes(now, today);
      final totalWorkHours = AttendanceRecord.calculateWorkHours(record.checkInTime, now);

      AttendanceStatus finalStatus = record.status;
      if (earlyLeaveMinutes > 0) {
        finalStatus = AttendanceStatus.earlyLeave;
      } else if (overtimeMinutes > 0) {
        finalStatus = AttendanceStatus.overtime;
      }

      final updatedRecord = record.copyWith(
        checkOutTime: now,
        checkOutGpsLat: lat,
        checkOutGpsLng: lng,
        isCheckOutGpsValid: isCheckOutGpsValid,
        earlyLeaveMinutes: earlyLeaveMinutes,
        overtimeMinutes: overtimeMinutes,
        totalWorkHours: totalWorkHours,
        status: finalStatus,
        updatedAt: now,
      );

      await _attendanceRepository.updateAttendance(updatedRecord);

      state = state.copyWith(
        todayAttendance: updatedRecord,
        isCheckingInOut: false,
        successMessage: 'Chấm công Ra thành công! Tổng giờ làm: ${totalWorkHours}h',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isCheckingInOut: false,
        errorMessage: 'Lỗi khi chấm công Ra: $e',
      );
      return false;
    }
  }
}

/// Provider for AttendanceNotifier.
final attendanceNotifierProvider =
    StateNotifierProvider<AttendanceNotifier, AttendanceCheckInState>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  final locationService = ref.watch(locationServiceProvider);
  return AttendanceNotifier(repo, locationService);
});
