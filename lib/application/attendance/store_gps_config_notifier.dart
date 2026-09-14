import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/attendance_remote_data_source.dart';
import '../../domain/attendance/attendance_repository.dart';
import '../../domain/attendance/geo_distance_helper.dart';
import '../../domain/attendance/store_gps_config.dart';
import '../auth/auth_providers.dart';
import 'attendance_providers.dart';

class StoreGpsConfigState {
  final String storeId;
  final StoreGpsConfig? config;
  final bool isLoading;
  final bool isSaving;
  final String? errorMessage;
  final String? successMessage;

  const StoreGpsConfigState({
    required this.storeId,
    this.config,
    this.isLoading = false,
    this.isSaving = false,
    this.errorMessage,
    this.successMessage,
  });

  StoreGpsConfigState copyWith({
    String? storeId,
    StoreGpsConfig? config,
    bool? isLoading,
    bool? isSaving,
    String? errorMessage,
    String? successMessage,
  }) {
    return StoreGpsConfigState(
      storeId: storeId ?? this.storeId,
      config: config ?? this.config,
      isLoading: isLoading ?? this.isLoading,
      isSaving: isSaving ?? this.isSaving,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class StoreGpsConfigNotifier extends StateNotifier<StoreGpsConfigState> {
  final AttendanceRepository _repository;
  final LocationService _locationService;

  StoreGpsConfigNotifier(
    this._repository,
    this._locationService, {
    required String initialStoreId,
  }) : super(StoreGpsConfigState(storeId: initialStoreId, isLoading: true)) {
    loadConfig(initialStoreId);
  }

  Future<void> loadConfig(String storeId) async {
    state = state.copyWith(storeId: storeId, isLoading: true, errorMessage: null);
    try {
      final config = await _repository.getStoreGpsConfig(storeId) ??
          StoreGpsConfig(
            storeId: storeId,
            latitude: 10.035000,
            longitude: 105.788000,
            allowedRadiusMeters: GeoDistanceHelper.defaultAllowedRadiusMeters,
          );
      state = state.copyWith(config: config, isLoading: false);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải cấu hình GPS chi nhánh: $e',
      );
    }
  }

  Future<GeoPoint?> getCurrentGpsCoordinates() async {
    return _locationService.getCurrentPosition();
  }

  Future<bool> saveConfig(StoreGpsConfig config) async {
    state = state.copyWith(isSaving: true, errorMessage: null, successMessage: null);
    try {
      await _repository.saveStoreGpsConfig(config);
      state = state.copyWith(
        config: config,
        isSaving: false,
        successMessage: 'Lưu cấu hình GPS chi nhánh thành công!',
      );
      return true;
    } catch (e) {
      state = state.copyWith(
        isSaving: false,
        errorMessage: 'Lỗi lưu cấu hình GPS: $e',
      );
      return false;
    }
  }
}

final storeGpsConfigNotifierProvider = StateNotifierProvider.autoDispose<
    StoreGpsConfigNotifier, StoreGpsConfigState>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  final locationService = ref.watch(locationServiceProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final user = ref.watch(authProvider);

  final isPureAdmin = user?.role.toLowerCase().trim() == 'admin';
  final effectiveStoreId = (isPureAdmin || user == null)
      ? currentStoreId
      : (user.storeId.isNotEmpty ? user.storeId : currentStoreId);

  return StoreGpsConfigNotifier(
    repo,
    locationService,
    initialStoreId: effectiveStoreId,
  );
});
