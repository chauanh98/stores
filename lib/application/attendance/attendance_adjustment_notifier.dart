import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/attendance/attendance_adjustment.dart';
import '../../domain/attendance/attendance_repository.dart';
import '../../domain/entities/user_account.dart';
import '../auth/auth_providers.dart';
import 'attendance_providers.dart';

class AttendanceAdjustmentState {
  final List<AttendanceAdjustment> adjustments;
  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  const AttendanceAdjustmentState({
    this.adjustments = const [],
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  AttendanceAdjustmentState copyWith({
    List<AttendanceAdjustment>? adjustments,
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
    bool clearErrorMessage = false,
    bool clearSuccessMessage = false,
  }) {
    return AttendanceAdjustmentState(
      adjustments: adjustments ?? this.adjustments,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearErrorMessage ? null : (errorMessage ?? this.errorMessage),
      successMessage: clearSuccessMessage ? null : (successMessage ?? this.successMessage),
    );
  }
}

class AttendanceAdjustmentNotifier extends StateNotifier<AttendanceAdjustmentState> {
  final AttendanceRepository _repository;
  final UserAccount? _currentUser;

  AttendanceAdjustmentNotifier(this._repository, this._currentUser)
      : super(const AttendanceAdjustmentState(isLoading: true)) {
    loadAdjustments();
  }

  Future<void> loadAdjustments() async {
    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    );
    try {
      final list = await _repository.getAdjustments(
        storeId: _currentUser?.role.toLowerCase().trim() == 'admin' ? null : _currentUser?.storeId,
        userId: _currentUser?.isStaff == true ? _currentUser?.username : null,
      );
      list.sort((a, b) => (b.submittedAt ?? DateTime.now()).compareTo(a.submittedAt ?? DateTime.now()));
      state = state.copyWith(adjustments: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải danh sách giải trình / điều chỉnh: $e',
      );
    }
  }

  Future<bool> submitRequest(AttendanceAdjustment request) async {
    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    );
    try {
      await _repository.requestAdjustment(request);
      await loadAdjustments();
      state = state.copyWith(
        successMessage: 'Đã gửi yêu cầu điều chỉnh thành công!',
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi gửi yêu cầu điều chỉnh: $e',
      );
      return false;
    }
  }

  Future<bool> approve({
    required String adjustmentId,
    required String reviewedBy,
    String? reviewNote,
  }) async {
    if (_currentUser?.canAdjustAttendance != true) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Bạn không có quyền duyệt điều chỉnh chấm công.',
      );
      return false;
    }

    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    );
    try {
      await _repository.reviewAdjustment(
        adjustmentId: adjustmentId,
        status: AdjustmentStatus.approved,
        reviewedBy: reviewedBy,
        reviewNote: reviewNote,
      );
      await loadAdjustments();
      state = state.copyWith(
        successMessage: 'Đã duyệt yêu cầu điều chỉnh công!',
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi duyệt điều chỉnh công: $e',
      );
      return false;
    }
  }

  Future<bool> reject({
    required String adjustmentId,
    required String reviewedBy,
    String? reviewNote,
  }) async {
    if (_currentUser?.canAdjustAttendance != true) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Bạn không có quyền duyệt điều chỉnh chấm công.',
      );
      return false;
    }

    state = state.copyWith(
      isLoading: true,
      clearErrorMessage: true,
      clearSuccessMessage: true,
    );
    try {
      await _repository.reviewAdjustment(
        adjustmentId: adjustmentId,
        status: AdjustmentStatus.rejected,
        reviewedBy: reviewedBy,
        reviewNote: reviewNote,
      );
      await loadAdjustments();
      state = state.copyWith(
        successMessage: 'Đã từ chối yêu cầu điều chỉnh.',
        isLoading: false,
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi từ chối điều chỉnh: $e',
      );
      return false;
    }
  }
}

final attendanceAdjustmentNotifierProvider = StateNotifierProvider.autoDispose<
    AttendanceAdjustmentNotifier, AttendanceAdjustmentState>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  final user = ref.watch(authProvider);
  return AttendanceAdjustmentNotifier(repo, user);
});
