import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/attendance/attendance_adjustment_notifier.dart';
import '../../../application/attendance/monthly_timesheet_notifier.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/attendance/attendance_record.dart';
import '../../../domain/entities/user_account.dart';
import '../widgets/attendance_status_badge.dart';

class MonthlyTimesheetPage extends ConsumerStatefulWidget {
  final bool isPersonalOnly;

  const MonthlyTimesheetPage({
    super.key,
    this.isPersonalOnly = false,
  });

  @override
  ConsumerState<MonthlyTimesheetPage> createState() =>
      _MonthlyTimesheetPageState();
}

class _MonthlyTimesheetPageState extends ConsumerState<MonthlyTimesheetPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authProvider);
    final isStaff = widget.isPersonalOnly || (user?.isStaff == true);
    _tabController = TabController(
      length: isStaff ? 1 : 2,
      vsync: this,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(monthlyTimesheetNotifierProvider.notifier).loadTimesheet();
      ref.read(attendanceAdjustmentNotifierProvider.notifier).loadAdjustments();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final timesheetState = ref.watch(monthlyTimesheetNotifierProvider);
    final adjustmentState = ref.watch(attendanceAdjustmentNotifierProvider);

    final isStaff = widget.isPersonalOnly || (user?.isStaff == true);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          isStaff ? 'Bảng công cá nhân' : 'Bảng chấm công & Duyệt công',
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: isStaff
            ? null
            : TabBar(
                controller: _tabController,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontWeight: FontWeight.normal,
                  fontSize: 13,
                ),
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                tabs: [
                  const Tab(text: 'BẢNG CÔNG TỔNG HỢP'),
                  Tab(
                    text:
                        'DUYỆT ĐIỀU CHỈNH (${adjustmentState.adjustments.where((a) => a.isPending).length})',
                  ),
                ],
              ),
      ),
      body: Column(
        children: [
          // Month Selector Bar
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final prevMonth = timesheetState.month == 1 ? 12 : timesheetState.month - 1;
                    final prevYear = timesheetState.month == 1 ? timesheetState.year - 1 : timesheetState.year;
                    ref.read(monthlyTimesheetNotifierProvider.notifier).changeMonth(prevYear, prevMonth);
                  },
                ),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.calendar_month, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          'Tháng ${timesheetState.month.toString().padLeft(2, '0')}/${timesheetState.year}',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final nextMonth = timesheetState.month == 12 ? 1 : timesheetState.month + 1;
                    final nextYear = timesheetState.month == 12 ? timesheetState.year + 1 : timesheetState.year;
                    ref.read(monthlyTimesheetNotifierProvider.notifier).changeMonth(nextYear, nextMonth);
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: isStaff
                ? _buildPersonalTimesheetView(timesheetState)
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildSummaryGridView(timesheetState),
                      _buildAdjustmentsReviewView(adjustmentState, user),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalTimesheetView(MonthlyTimesheetState state) {
    final personal = state.personalSummary;
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final records = personal?.records ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // KPI card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _buildKpiItem('Tổng giờ làm', '${personal?.totalHoursWorked ?? 0}h', AppColors.primary),
                ),
                Expanded(
                  child: _buildKpiItem('Ca hoàn tất', '${personal?.shiftsCompleted ?? 0}', AppColors.success),
                ),
                Expanded(
                  child: _buildKpiItem('Đi muộn', '${personal?.lateCount ?? 0}', AppColors.warning),
                ),
                Expanded(
                  child: _buildKpiItem('Về sớm', '${personal?.earlyLeaveCount ?? 0}', const Color(0xFFC2410C)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text('Chi tiết các ngày làm việc:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),
          if (records.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(32.0),
                child: Text('Không có dữ liệu chấm công trong tháng này.'),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: records.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final r = records[index];
                return _buildRecordTile(r);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryGridView(MonthlyTimesheetState state) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final summaries = state.staffSummaries;
    if (summaries.isEmpty) {
      return const Center(child: Text('Không có dữ liệu chấm công tháng này.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: summaries.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = summaries[index];
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: AppColors.primary.withOpacity(0.15),
              child: Text(
                item.userName.isNotEmpty ? item.userName[0].toUpperCase() : 'NV',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
              ),
            ),
            title: Text(item.userName, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              '${item.totalHoursWorked} giờ • ${item.shiftsCompleted} ca • Muộn: ${item.lateCount} lần',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            children: [
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _buildKpiItem('Tổng giờ', '${item.totalHoursWorked}h', AppColors.primary),
                        ),
                        Expanded(
                          child: _buildKpiItem('Ca làm', '${item.shiftsCompleted}', AppColors.success),
                        ),
                        Expanded(
                          child: _buildKpiItem('Đi muộn', '${item.lateCount}', AppColors.warning),
                        ),
                        Expanded(
                          child: _buildKpiItem('Tăng ca', '${item.overtimeMinutes}p', AppColors.supervisor),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Text('Nhật ký chấm công:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    ...item.records.map((r) => _buildRecordTile(r)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAdjustmentsReviewView(
    AttendanceAdjustmentState state,
    UserAccount? user,
  ) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final adjustments = state.adjustments;
    if (adjustments.isEmpty) {
      return const Center(child: Text('Không có yêu cầu điều chỉnh công nào.'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: adjustments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final adj = adjustments[index];
        final inStr = '${adj.requestedCheckIn.hour.toString().padLeft(2, '0')}:${adj.requestedCheckIn.minute.toString().padLeft(2, '0')}';
        final outStr = '${adj.requestedCheckOut.hour.toString().padLeft(2, '0')}:${adj.requestedCheckOut.minute.toString().padLeft(2, '0')}';
        final dateStr = '${adj.requestedCheckIn.day}/${adj.requestedCheckIn.month}/${adj.requestedCheckIn.year}';

        Color statusColor = AppColors.warning;
        if (adj.isApproved) statusColor = AppColors.success;
        if (adj.isRejected) statusColor = AppColors.danger;

        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.border),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        adj.userName,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        adj.status.label,
                        style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text('Ngày: $dateStr • Giờ xin điều chỉnh: $inStr - $outStr', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 4),
                Text(
                  'Lý do: "${adj.reason}"',
                  style: const TextStyle(fontSize: 13, fontStyle: FontStyle.italic, color: AppColors.textSecondary),
                ),
                if (adj.reviewedBy != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Người duyệt: ${adj.reviewedBy}${adj.reviewNote != null ? ' (Ghi chú: ${adj.reviewNote})' : ''}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
                if (adj.isPending && (user?.canAdjustAttendance == true)) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Flexible(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            final user = ref.read(authProvider);
                            ref.read(attendanceAdjustmentNotifierProvider.notifier).reject(
                                  adjustmentId: adj.id,
                                  reviewedBy: user?.username ?? 'manager',
                                );
                          },
                          child: const Text('Từ chối', maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () {
                            final user = ref.read(authProvider);
                            ref.read(attendanceAdjustmentNotifierProvider.notifier).approve(
                                  adjustmentId: adj.id,
                                  reviewedBy: user?.username ?? 'manager',
                                );
                          },
                          child: const Text('Duyệt công', maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRecordTile(AttendanceRecord r) {
    final dateStr = '${r.date.day.toString().padLeft(2, '0')}/${r.date.month.toString().padLeft(2, '0')}';
    final inStr = '${r.checkInTime.hour.toString().padLeft(2, '0')}:${r.checkInTime.minute.toString().padLeft(2, '0')}';
    final outStr = r.checkOutTime != null
        ? '${r.checkOutTime!.hour.toString().padLeft(2, '0')}:${r.checkOutTime!.minute.toString().padLeft(2, '0')}'
        : '--:--';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(dateStr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '${r.shiftName} ($inStr - $outStr)',
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 6),
          Text('${r.totalWorkHours}h', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(width: 6),
          Flexible(
            child: AttendanceStatusBadge(
              status: r.status,
              lateMinutes: r.lateMinutes,
              earlyLeaveMinutes: r.earlyLeaveMinutes,
              overtimeMinutes: r.overtimeMinutes,
              isGpsValid: r.isGpsValid,
              isWorking: r.isWorking,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiItem(String title, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          title,
          style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
