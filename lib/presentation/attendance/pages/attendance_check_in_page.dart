import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/attendance/attendance_notifier.dart';
import '../../../application/attendance/attendance_providers.dart';
import '../../../application/attendance/monthly_timesheet_notifier.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/attendance/attendance_record.dart';
import '../../../domain/attendance/shift.dart';
import '../widgets/adjustment_dialog.dart';
import '../widgets/attendance_status_badge.dart';
import '../widgets/gps_status_card.dart';
import '../widgets/shift_selector_card.dart';
import 'monthly_timesheet_page.dart';

class AttendanceCheckInPage extends ConsumerStatefulWidget {
  const AttendanceCheckInPage({super.key});

  @override
  ConsumerState<AttendanceCheckInPage> createState() =>
      _AttendanceCheckInPageState();
}

class _AttendanceCheckInPageState extends ConsumerState<AttendanceCheckInPage> {
  final _explanationController = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initAttendance();
    });
  }

  @override
  void dispose() {
    _explanationController.dispose();
    super.dispose();
  }

  void _initAttendance() {
    final user = ref.read(authProvider);
    final storeId = ref.read(currentStoreIdProvider);
    final shiftsState = ref.read(shiftListNotifierProvider);
    final initialShift =
        Shift.findBestShiftForTime(shiftsState.shifts, DateTime.now());

    if (user != null) {
      ref.read(attendanceNotifierProvider.notifier).init(
            storeId: storeId,
            userId: user.username,
            initialShift: initialShift,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final storeId = ref.watch(currentStoreIdProvider);
    final storeNameAsync = ref.watch(currentStoreNameProvider);
    final shiftsState = ref.watch(shiftListNotifierProvider);
    final attendanceState = ref.watch(attendanceNotifierProvider);
    final timesheetState = ref.watch(monthlyTimesheetNotifierProvider);

    ref.listen(shiftListNotifierProvider, (prev, next) {
      if (next.shifts.isNotEmpty) {
        final currentSelected =
            ref.read(attendanceNotifierProvider).selectedShift;
        final isOrphanOrNull = currentSelected == null ||
            !next.shifts.any((s) => s.id == currentSelected.id);
        if (isOrphanOrNull && user != null) {
          final bestShift =
              Shift.findBestShiftForTime(next.shifts, DateTime.now()) ??
                  next.shifts.first;
          ref.read(attendanceNotifierProvider.notifier).selectShift(
                bestShift,
                storeId: storeId,
                userId: user.username,
              );
        }
      }
    });

    final storeDisplayName = storeNameAsync.valueOrNull ??
        (storeId.isNotEmpty ? storeId : 'Chi nhánh');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Chấm công GPS & Quản lý Ca',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        actions: [
          IconButton(
            icon: const Icon(Icons.history, color: AppColors.textPrimary),
            tooltip: 'Bảng công cá nhân',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      const MonthlyTimesheetPage(isPersonalOnly: true),
                ),
              );
            },
          ),
        ],
      ),
      body: attendanceState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await ref
                    .read(attendanceNotifierProvider.notifier)
                    .refreshLocation(storeId: storeId);
                await ref
                    .read(monthlyTimesheetNotifierProvider.notifier)
                    .loadTimesheet();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Banner feedback messages
                    if (attendanceState.errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.dangerLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline,
                                color: AppColors.danger, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                attendanceState.errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.danger,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    if (attendanceState.successMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                color: AppColors.success, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                attendanceState.successMessage!,
                                style: const TextStyle(
                                  color: AppColors.success,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // Staff Welcome & Store Card
                    Card(
                      elevation: 0,
                      color: AppColors.surface,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: const BorderSide(color: AppColors.border),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor:
                                  AppColors.primary.withOpacity(0.15),
                              child: Text(
                                (user?.name.isNotEmpty == true)
                                    ? user!.name[0].toUpperCase()
                                    : 'NV',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user?.name ?? 'Nhân viên',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      const Icon(Icons.store,
                                          size: 14,
                                          color: AppColors.textSecondary),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          storeDisplayName,
                                          style: const TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textSecondary,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // GPS Status Card
                    GpsStatusCard(
                      distanceMeters: attendanceState.distanceToStoreMeters,
                      isWithinRadius: attendanceState.isWithinRadius,
                      storeConfig: attendanceState.storeGpsConfig,
                      explanationController: _explanationController,
                      onRefreshLocation: () {
                        ref
                            .read(attendanceNotifierProvider.notifier)
                            .refreshLocation(storeId: storeId);
                      },
                      onSelectSimulatedLocation: (point) {
                        ref
                            .read(attendanceNotifierProvider.notifier)
                            .setSimulatedCoordinates(point, storeId: storeId);
                      },
                    ),
                    const SizedBox(height: 14),

                    // Shift Selector (only active if not yet checked in)
                    if (attendanceState.todayAttendance == null)
                      ShiftSelectorCard(
                        shifts: shiftsState.shifts,
                        selectedShift: attendanceState.selectedShift,
                        currentTime: DateTime.now(),
                        onShiftSelected: (shift) {
                          if (user != null) {
                            ref
                                .read(attendanceNotifierProvider.notifier)
                                .selectShift(
                                  shift,
                                  storeId: storeId,
                                  userId: user.username,
                                );
                          }
                        },
                      )
                    else
                      _buildActiveShiftCard(attendanceState.todayAttendance!),

                    const SizedBox(height: 18),

                    // Action Buttons (Check-in / Check-out)
                    _buildActionButtons(user, storeId, attendanceState),

                    const SizedBox(height: 24),

                    // Personal Monthly Timesheet KPI Card
                    _buildPersonalTimesheetSummary(timesheetState),

                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildActiveShiftCard(AttendanceRecord record) {
    final inTimeStr =
        '${record.checkInTime.hour.toString().padLeft(2, '0')}:${record.checkInTime.minute.toString().padLeft(2, '0')}';
    final outTimeStr = record.checkOutTime != null
        ? '${record.checkOutTime!.hour.toString().padLeft(2, '0')}:${record.checkOutTime!.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.work_history,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    record.shiftName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                AttendanceStatusBadge(
                  status: record.status,
                  lateMinutes: record.lateMinutes,
                  earlyLeaveMinutes: record.earlyLeaveMinutes,
                  overtimeMinutes: record.overtimeMinutes,
                  isGpsValid: record.isGpsValid,
                  isWorking: record.isWorking,
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('Giờ vào',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        inTimeStr,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.success,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(height: 28, width: 1, color: AppColors.divider),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Giờ ra',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        outTimeStr,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: record.checkOutTime != null
                              ? AppColors.danger
                              : AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Container(height: 28, width: 1, color: AppColors.divider),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Tổng giờ làm',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 4),
                      Text(
                        '${record.totalWorkHours}h',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primaryDark,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    dynamic user,
    String storeId,
    AttendanceCheckInState state,
  ) {
    if (state.canCheckIn) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
          icon: state.isCheckingInOut
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppColors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.login, size: 22),
          label: Text(
            state.isCheckingInOut ? 'ĐANG XÁC THỰC...' : 'CHẤM CÔNG VÀO',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onPressed: state.isCheckingInOut || user == null
              ? null
              : () async {
                  final explanation = _explanationController.text.trim();
                  await ref.read(attendanceNotifierProvider.notifier).checkIn(
                        user: user,
                        storeId: storeId,
                        explanationReason:
                            explanation.isNotEmpty ? explanation : null,
                      );
                  _explanationController.clear();
                },
        ),
      );
    } else if (state.canCheckOut) {
      return SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.dangerMedium,
            foregroundColor: AppColors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 2,
          ),
          icon: state.isCheckingInOut
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: AppColors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Icon(Icons.logout, size: 22),
          label: Text(
            state.isCheckingInOut ? 'ĐANG LƯU GIỜ RA...' : 'CHẤM CÔNG RA',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onPressed: state.isCheckingInOut || user == null
              ? null
              : () async {
                  final explanation = _explanationController.text.trim();
                  await ref.read(attendanceNotifierProvider.notifier).checkOut(
                        user: user,
                        storeId: storeId,
                        explanationReason:
                            explanation.isNotEmpty ? explanation : null,
                      );
                  _explanationController.clear();
                },
        ),
      );
    } else {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.successLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success.withOpacity(0.4)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: AppColors.success),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Bạn đã hoàn thành ca làm việc hôm nay!',
                style: TextStyle(
                  color: AppColors.success,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildPersonalTimesheetSummary(MonthlyTimesheetState timesheetState) {
    final personal = timesheetState.personalSummary;
    final totalHours = personal?.totalHoursWorked ?? 0.0;
    final completedShifts = personal?.shiftsCompleted ?? 0;
    final lateCount = personal?.lateCount ?? 0;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.date_range,
                    color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Bảng công tháng này',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const MonthlyTimesheetPage(isPersonalOnly: true),
                      ),
                    );
                  },
                  child: const Text('Xem chi tiết >'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    'Tổng giờ làm',
                    '${totalHours}h',
                    AppColors.primary,
                    Icons.access_time,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    'Ca hoàn thành',
                    '$completedShifts',
                    AppColors.success,
                    Icons.task_alt,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    'Số lần đi muộn',
                    '$lateCount',
                    lateCount > 0 ? AppColors.warning : AppColors.textSecondary,
                    Icons.alarm_off,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(40),
                foregroundColor: AppColors.primary,
              ),
              onPressed: () {
                final user = ref.read(authProvider);
                final storeId = ref.read(currentStoreIdProvider);
                if (user == null) return;

                showDialog(
                  context: context,
                  builder: (ctx) => RequestAdjustmentDialog(
                    userId: user.username,
                    userName: user.name,
                    storeId: storeId,
                    onSubmit: (req) {
                      ref
                          .read(monthlyTimesheetNotifierProvider.notifier)
                          .loadTimesheet();
                    },
                  ),
                );
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.edit_calendar, size: 18),
                  SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Gửi yêu cầu điều chỉnh / giải trình công',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile(
      String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            textAlign: TextAlign.center,
            style:
                const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
