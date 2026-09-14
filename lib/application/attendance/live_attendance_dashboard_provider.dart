import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/attendance/attendance_record.dart';
import '../../domain/attendance/attendance_repository.dart';
import '../../domain/entities/user_account.dart';
import '../auth/auth_providers.dart';
import 'attendance_providers.dart';

class LiveAttendanceState {
  final String storeId;
  final DateTime date;
  final List<AttendanceRecord> allRecords;
  final List<AttendanceRecord> workingStaff;
  final List<AttendanceRecord> lateStaff;
  final List<AttendanceRecord> checkedOutStaff;
  final List<UserAccount> notArrivedStaff;
  final bool isLoading;
  final String? errorMessage;

  const LiveAttendanceState({
    required this.storeId,
    required this.date,
    this.allRecords = const [],
    this.workingStaff = const [],
    this.lateStaff = const [],
    this.checkedOutStaff = const [],
    this.notArrivedStaff = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  int get workingCount => workingStaff.length;
  int get lateCount => lateStaff.length;
  int get notArrivedCount => notArrivedStaff.length;
  int get checkedOutCount => checkedOutStaff.length;

  LiveAttendanceState copyWith({
    String? storeId,
    DateTime? date,
    List<AttendanceRecord>? allRecords,
    List<AttendanceRecord>? workingStaff,
    List<AttendanceRecord>? lateStaff,
    List<AttendanceRecord>? checkedOutStaff,
    List<UserAccount>? notArrivedStaff,
    bool? isLoading,
    String? errorMessage,
  }) {
    return LiveAttendanceState(
      storeId: storeId ?? this.storeId,
      date: date ?? this.date,
      allRecords: allRecords ?? this.allRecords,
      workingStaff: workingStaff ?? this.workingStaff,
      lateStaff: lateStaff ?? this.lateStaff,
      checkedOutStaff: checkedOutStaff ?? this.checkedOutStaff,
      notArrivedStaff: notArrivedStaff ?? this.notArrivedStaff,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class LiveAttendanceDashboardNotifier extends StateNotifier<LiveAttendanceState> {
  final AttendanceRepository _repository;
  final FirebaseDatabase? _db;
  final UserAccount? _currentUser;
  StreamSubscription? _streamSubscription;

  LiveAttendanceDashboardNotifier(
    this._repository,
    this._currentUser, {
    FirebaseDatabase? db,
    String? initialStoreId,
  }) : _db = db,
        super(
          LiveAttendanceState(
            storeId: _resolveStoreId(_currentUser, initialStoreId),
            date: DateTime.now(),
            isLoading: true,
          ),
        ) {
    _initDashboard();
  }

  static String _resolveStoreId(UserAccount? user, String? requestedStoreId) {
    final isPureAdmin = user?.role.toLowerCase().trim() == 'admin';
    if (!isPureAdmin && user != null) {
      return user.storeId.isNotEmpty ? user.storeId : 'store_001';
    }
    return requestedStoreId ?? user?.storeId ?? 'store_001';
  }

  void _initDashboard() {
    _subscribeToLiveAttendances();
    loadDashboard();
  }

  void _subscribeToLiveAttendances() {
    _streamSubscription?.cancel();
    final today = DateTime(state.date.year, state.date.month, state.date.day);
    _streamSubscription = _repository
        .watchTodayAttendances(storeId: state.storeId, date: today)
        .listen(
      (records) {
        _processRecords(records);
      },
      onError: (e) {
        state = state.copyWith(errorMessage: 'Lỗi đồng bộ trực tiếp: $e');
      },
    );
  }

  Future<void> changeStore(String newStoreId) async {
    // Role-based scoping check:
    // Only pure admin can switch stores. Supervisors and staff are locked to their assigned storeId!
    final isPureAdmin = _currentUser?.role.toLowerCase().trim() == 'admin';
    if (!isPureAdmin) {
      return;
    }

    if (state.storeId == newStoreId) return;

    state = state.copyWith(storeId: newStoreId, isLoading: true);
    _subscribeToLiveAttendances();
    await loadDashboard();
  }

  Future<void> loadDashboard() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final today = DateTime(state.date.year, state.date.month, state.date.day);
      final records = await _repository.getAttendances(
        storeId: state.storeId,
        date: today,
      );

      await _processRecords(records);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải dữ liệu chấm công: $e',
      );
    }
  }

  Future<void> _processRecords(List<AttendanceRecord> records) async {
    final working = records.where((r) => r.isWorking).toList();
    final late = records.where((r) => r.lateMinutes > 0).toList();
    final checkedOut = records.where((r) => !r.isWorking).toList();

    // Fetch staff for this store to determine who hasn't arrived
    List<UserAccount> notArrived = [];
    try {
      final storeStaff = await _fetchStaffForStore(state.storeId);
      final checkedInUserIds = records.map((r) => r.userId.toLowerCase()).toSet();
      notArrived = storeStaff
          .where((s) => !checkedInUserIds.contains(s.username.toLowerCase()))
          .toList();
    } catch (_) {
      // Fallback if accounts could not be fetched
    }

    state = state.copyWith(
      allRecords: records,
      workingStaff: working,
      lateStaff: late,
      checkedOutStaff: checkedOut,
      notArrivedStaff: notArrived,
      isLoading: false,
    );
  }

  Future<List<UserAccount>> _fetchStaffForStore(String storeId) async {
    if (_db == null) return [];
    try {
      final snap = await _db.ref('stores/accounts').get();
      if (!snap.exists || snap.value == null) return [];
      final data = Map<String, dynamic>.from(snap.value as Map);
      final List<UserAccount> staffList = [];
      data.forEach((username, value) {
        if (value is Map) {
          final account = UserAccount.fromMap(username, value);
          if (account.storeId == storeId && account.requiresAttendance) {
            staffList.add(account);
          }
        }
      });
      return staffList;
    } catch (_) {
      return [];
    }
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }
}

final liveAttendanceDashboardProvider = StateNotifierProvider.autoDispose<
    LiveAttendanceDashboardNotifier, LiveAttendanceState>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  final user = ref.watch(authProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);

  FirebaseDatabase? db;
  try {
    db = FirebaseDatabase.instance;
  } catch (_) {}

  return LiveAttendanceDashboardNotifier(
    repo,
    user,
    db: db,
    initialStoreId: currentStoreId,
  );
});
