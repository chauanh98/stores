import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/attendance_remote_data_source.dart';
import '../../data/repositories/attendance_repository_impl.dart';
import '../../domain/attendance/attendance_repository.dart';
import '../../domain/attendance/shift.dart';
import '../../domain/attendance/shift_repository.dart';

// ==========================================
// INFRASTRUCTURE & REPOSITORY PROVIDERS
// ==========================================

/// Location service provider (can be overridden in tests).
final locationServiceProvider = Provider<LocationService>((ref) {
  return DefaultLocationService();
});

/// Attendance remote data source provider.
final attendanceRemoteDataSourceProvider =
    Provider<AttendanceRemoteDataSource>((ref) {
  final locationService = ref.watch(locationServiceProvider);
  FirebaseDatabase? db;
  try {
    db = FirebaseDatabase.instance;
  } catch (_) {}
  return AttendanceRemoteDataSource(
    db: db,
    locationService: locationService,
  );
});

/// Attendance repository implementation provider.
final attendanceRepositoryImplProvider =
    Provider<AttendanceRepositoryImpl>((ref) {
  final dataSource = ref.watch(attendanceRemoteDataSourceProvider);
  return AttendanceRepositoryImpl(dataSource);
});

/// Attendance repository interface provider.
final attendanceRepositoryProvider = Provider<AttendanceRepository>((ref) {
  return ref.watch(attendanceRepositoryImplProvider);
});

/// Shift repository interface provider.
final shiftRepositoryProvider = Provider<ShiftRepository>((ref) {
  return ref.watch(attendanceRepositoryImplProvider);
});

// ==========================================
// SHIFT LIST NOTIFIER & PROVIDER
// ==========================================

class ShiftListState {
  final List<Shift> shifts;
  final bool isLoading;
  final String? errorMessage;

  const ShiftListState({
    this.shifts = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  ShiftListState copyWith({
    List<Shift>? shifts,
    bool? isLoading,
    String? errorMessage,
  }) {
    return ShiftListState(
      shifts: shifts ?? this.shifts,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class ShiftListNotifier extends StateNotifier<ShiftListState> {
  final ShiftRepository _repository;

  ShiftListNotifier(this._repository)
      : super(ShiftListState(shifts: Shift.defaultShifts(), isLoading: false)) {
    loadShifts();
  }

  Future<void> loadShifts() async {
    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final list = await _repository.getShifts();
      state = state.copyWith(shifts: list, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải danh sách ca: $e',
        shifts: Shift.defaultShifts(),
      );
    }
  }

  Future<bool> saveShift(Shift shift) async {
    try {
      await _repository.saveShift(shift);
      await loadShifts();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Lỗi lưu ca làm: $e');
      return false;
    }
  }

  Future<bool> deleteShift(String shiftId) async {
    try {
      await _repository.deleteShift(shiftId);
      await loadShifts();
      return true;
    } catch (e) {
      state = state.copyWith(errorMessage: 'Lỗi xóa ca làm: $e');
      return false;
    }
  }
}

final shiftListNotifierProvider =
    StateNotifierProvider<ShiftListNotifier, ShiftListState>((ref) {
  final repo = ref.watch(shiftRepositoryProvider);
  return ShiftListNotifier(repo);
});
