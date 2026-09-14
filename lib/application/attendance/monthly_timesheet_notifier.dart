import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/attendance/attendance_record.dart';
import '../../domain/attendance/attendance_repository.dart';
import '../../domain/entities/user_account.dart';
import '../auth/auth_providers.dart';
import 'attendance_providers.dart';

/// Aggregated monthly summary for an individual staff member.
class StaffTimesheetSummary {
  final String userId;
  final String userName;
  final String storeId;
  final double totalHoursWorked;
  final int shiftsCompleted;
  final int lateCount;
  final int earlyLeaveCount;
  final int overtimeMinutes;
  final List<AttendanceRecord> records;

  const StaffTimesheetSummary({
    required this.userId,
    required this.userName,
    required this.storeId,
    required this.totalHoursWorked,
    required this.shiftsCompleted,
    required this.lateCount,
    required this.earlyLeaveCount,
    required this.overtimeMinutes,
    required this.records,
  });

  StaffTimesheetSummary copyWith({
    String? userId,
    String? userName,
    String? storeId,
    double? totalHoursWorked,
    int? shiftsCompleted,
    int? lateCount,
    int? earlyLeaveCount,
    int? overtimeMinutes,
    List<AttendanceRecord>? records,
  }) {
    return StaffTimesheetSummary(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      storeId: storeId ?? this.storeId,
      totalHoursWorked: totalHoursWorked ?? this.totalHoursWorked,
      shiftsCompleted: shiftsCompleted ?? this.shiftsCompleted,
      lateCount: lateCount ?? this.lateCount,
      earlyLeaveCount: earlyLeaveCount ?? this.earlyLeaveCount,
      overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
      records: records ?? this.records,
    );
  }
}

class MonthlyTimesheetState {
  final int year;
  final int month;
  final String storeId;
  final List<AttendanceRecord> records;
  final StaffTimesheetSummary? personalSummary;
  final List<StaffTimesheetSummary> staffSummaries;
  final bool isLoading;
  final String? errorMessage;

  const MonthlyTimesheetState({
    required this.year,
    required this.month,
    required this.storeId,
    this.records = const [],
    this.personalSummary,
    this.staffSummaries = const [],
    this.isLoading = false,
    this.errorMessage,
  });

  MonthlyTimesheetState copyWith({
    int? year,
    int? month,
    String? storeId,
    List<AttendanceRecord>? records,
    StaffTimesheetSummary? personalSummary,
    List<StaffTimesheetSummary>? staffSummaries,
    bool? isLoading,
    String? errorMessage,
  }) {
    return MonthlyTimesheetState(
      year: year ?? this.year,
      month: month ?? this.month,
      storeId: storeId ?? this.storeId,
      records: records ?? this.records,
      personalSummary: personalSummary ?? this.personalSummary,
      staffSummaries: staffSummaries ?? this.staffSummaries,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
    );
  }
}

class MonthlyTimesheetNotifier extends StateNotifier<MonthlyTimesheetState> {
  final AttendanceRepository _repository;
  final UserAccount? _currentUser;

  MonthlyTimesheetNotifier(
    this._repository,
    this._currentUser, {
    String? initialStoreId,
    int? initialYear,
    int? initialMonth,
  }) : super(
          MonthlyTimesheetState(
            year: initialYear ?? DateTime.now().year,
            month: initialMonth ?? DateTime.now().month,
            storeId: _resolveStoreId(_currentUser, initialStoreId),
            isLoading: true,
          ),
        ) {
    loadTimesheet();
  }

  static String _resolveStoreId(UserAccount? user, String? initialStoreId) {
    final isPureAdmin = user?.role.toLowerCase().trim() == 'admin';
    if (!isPureAdmin && user != null) {
      return user.storeId.isNotEmpty ? user.storeId : 'store_001';
    }
    return initialStoreId ?? user?.storeId ?? 'store_001';
  }

  Future<void> changeMonth(int year, int month) async {
    state = state.copyWith(year: year, month: month, isLoading: true);
    await loadTimesheet();
  }

  Future<void> changeStore(String storeId) async {
    final isPureAdmin = _currentUser?.role.toLowerCase().trim() == 'admin';
    if (!isPureAdmin) return;
    state = state.copyWith(storeId: storeId, isLoading: true);
    await loadTimesheet();
  }

  Future<void> loadTimesheet() async {
    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final records = await _repository.getMonthlyAttendances(
        storeId: state.storeId,
        year: state.year,
        month: state.month,
      );

      // Group records by staff member
      final Map<String, List<AttendanceRecord>> grouped = {};
      for (final r in records) {
        grouped.putIfAbsent(r.userId, () => []).add(r);
      }

      final List<StaffTimesheetSummary> summaries = [];
      grouped.forEach((userId, userRecords) {
        userRecords.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
        final userName = userRecords.first.userName;
        final storeId = userRecords.first.storeId;

        double totalHours = 0.0;
        int completedShifts = 0;
        int lateCount = 0;
        int earlyLeaveCount = 0;
        int overtimeMins = 0;

        for (final rec in userRecords) {
          totalHours += rec.totalWorkHours;
          if (rec.checkOutTime != null) {
            completedShifts++;
          }
          if (rec.lateMinutes > 0) {
            lateCount++;
          }
          if (rec.earlyLeaveMinutes > 0) {
            earlyLeaveCount++;
          }
          overtimeMins += rec.overtimeMinutes;
        }

        summaries.add(
          StaffTimesheetSummary(
            userId: userId,
            userName: userName,
            storeId: storeId,
            totalHoursWorked: double.parse(totalHours.toStringAsFixed(2)),
            shiftsCompleted: completedShifts,
            lateCount: lateCount,
            earlyLeaveCount: earlyLeaveCount,
            overtimeMinutes: overtimeMins,
            records: userRecords,
          ),
        );
      });

      // Sort summaries by staff name
      summaries.sort((a, b) => a.userName.compareTo(b.userName));

      // Calculate personal summary if user is logged in
      StaffTimesheetSummary? personal;
      if (_currentUser != null) {
        personal = summaries.firstWhere(
          (s) => s.userId.toLowerCase() == _currentUser.username.toLowerCase(),
          orElse: () => StaffTimesheetSummary(
            userId: _currentUser.username,
            userName: _currentUser.name,
            storeId: state.storeId,
            totalHoursWorked: 0.0,
            shiftsCompleted: 0,
            lateCount: 0,
            earlyLeaveCount: 0,
            overtimeMinutes: 0,
            records: const [],
          ),
        );
      }

      state = state.copyWith(
        records: records,
        staffSummaries: summaries,
        personalSummary: personal,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Lỗi tải bảng chấm công: $e',
      );
    }
  }
}

final monthlyTimesheetNotifierProvider = StateNotifierProvider.autoDispose<
    MonthlyTimesheetNotifier, MonthlyTimesheetState>((ref) {
  final repo = ref.watch(attendanceRepositoryProvider);
  final user = ref.watch(authProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);

  return MonthlyTimesheetNotifier(
    repo,
    user,
    initialStoreId: currentStoreId,
  );
});
