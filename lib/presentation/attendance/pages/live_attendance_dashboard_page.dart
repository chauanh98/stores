import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/attendance/live_attendance_dashboard_provider.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../domain/attendance/attendance_record.dart';
import '../widgets/attendance_status_badge.dart';
import 'monthly_timesheet_page.dart';
import 'shift_config_page.dart';

class LiveAttendanceDashboardPage extends ConsumerStatefulWidget {
  const LiveAttendanceDashboardPage({super.key});

  @override
  ConsumerState<LiveAttendanceDashboardPage> createState() =>
      _LiveAttendanceDashboardPageState();
}

class _LiveAttendanceDashboardPageState
    extends ConsumerState<LiveAttendanceDashboardPage> {
  int _selectedFilterIndex =
      0; // 0: Tất cả, 1: Đang làm, 2: Đi muộn, 3: Chưa đến, 4: Đã về

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final dashboardState = ref.watch(liveAttendanceDashboardProvider);
    final storeNamesAsync = ref.watch(availableStoresProvider);
    final storeNames = storeNamesAsync.valueOrNull ?? {};

    final currentStoreId = dashboardState.storeId;
    final currentStoreName = StoreResolverHelper.resolveStoreName(
      currentStoreId,
      storeNames: storeNames,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Giám sát chấm công trực tiếp',
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
            icon: const Icon(Icons.table_chart, color: AppColors.textPrimary),
            tooltip: 'Bảng công tổng hợp',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const MonthlyTimesheetPage(),
                ),
              );
            },
          ),
          if (user?.isAdmin == true || user?.isSupervisor == true)
            IconButton(
              icon: const Icon(Icons.settings, color: AppColors.textPrimary),
              tooltip: 'Cấu hình Ca & GPS',
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ShiftConfigPage(),
                  ),
                );
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Store Selector Bar (Admin can toggle / Supervisor locked)
          Container(
            color: AppColors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              children: [
                const Icon(Icons.store, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: user?.role.toLowerCase().trim() == 'admin'
                      ? DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: storeNames.containsKey(currentStoreId)
                                ? currentStoreId
                                : null,
                            hint: Text(
                              currentStoreName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            isExpanded: true,
                            items: storeNames.entries.map((e) {
                              return DropdownMenuItem(
                                value: e.key,
                                child: Text(
                                  e.value,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (newStore) {
                              if (newStore != null) {
                                ref
                                    .read(liveAttendanceDashboardProvider
                                        .notifier)
                                    .changeStore(newStore);
                              }
                            },
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceHighlight,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            currentStoreName,
                            style: const TextStyle(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, color: AppColors.primary),
                  tooltip: 'Tải lại',
                  onPressed: () {
                    ref
                        .read(liveAttendanceDashboardProvider.notifier)
                        .loadDashboard();
                  },
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // KPI Cards Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: _buildKpiCard(
                    title: 'Đang làm việc',
                    count: dashboardState.workingCount,
                    color: AppColors.primary,
                    icon: Icons.work,
                    isSelected: _selectedFilterIndex == 1,
                    onTap: () => setState(() => _selectedFilterIndex = 1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard(
                    title: 'Đi muộn hôm nay',
                    count: dashboardState.lateCount,
                    color: AppColors.warning,
                    icon: Icons.warning_amber_rounded,
                    isSelected: _selectedFilterIndex == 2,
                    onTap: () => setState(() => _selectedFilterIndex = 2),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard(
                    title: 'Chưa đến',
                    count: dashboardState.notArrivedCount,
                    color: AppColors.danger,
                    icon: Icons.person_off,
                    isSelected: _selectedFilterIndex == 3,
                    onTap: () => setState(() => _selectedFilterIndex = 3),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildKpiCard(
                    title: 'Đã hoàn tất',
                    count: dashboardState.checkedOutCount,
                    color: AppColors.success,
                    icon: Icons.done_all,
                    isSelected: _selectedFilterIndex == 4,
                    onTap: () => setState(() => _selectedFilterIndex = 4),
                  ),
                ),
              ],
            ),
          ),

          // Filter chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                _buildFilterChip(
                    'Tất cả (${dashboardState.allRecords.length})', 0),
                const SizedBox(width: 8),
                _buildFilterChip(
                    'Đang làm (${dashboardState.workingCount})', 1),
                const SizedBox(width: 8),
                _buildFilterChip('Đi muộn (${dashboardState.lateCount})', 2),
                const SizedBox(width: 8),
                _buildFilterChip(
                    'Chưa đến (${dashboardState.notArrivedCount})', 3),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Main Content List
          Expanded(
            child: dashboardState.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildContentList(dashboardState, storeNames),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, int index) {
    final isSelected = _selectedFilterIndex == index;
    return ChoiceChip(
      showCheckmark: false,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? AppColors.white : AppColors.textPrimary,
        ),
      ),
      selected: isSelected,
      selectedColor: AppColors.primary,
      backgroundColor: Colors.grey.shade100,
      side: BorderSide(
        color: isSelected ? AppColors.primary : AppColors.border,
        width: 1.0,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      onSelected: (_) => setState(() => _selectedFilterIndex = index),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? color : AppColors.border,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              textAlign: TextAlign.center,
              maxLines: 2,
              style:
                  const TextStyle(fontSize: 10, color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentList(
      LiveAttendanceState state, Map<String, String> storeNames) {
    // If filter is "Chưa đến" (absent / not arrived)
    if (_selectedFilterIndex == 3) {
      if (state.notArrivedStaff.isEmpty) {
        return const Center(
          child: Text('Tất cả nhân viên ca hôm nay đều đã điểm danh!'),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: state.notArrivedStaff.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final staff = state.notArrivedStaff[index];
          final staffStoreName = StoreResolverHelper.resolveStoreName(
            staff.storeId,
            storeNames: storeNames,
          );
          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: const BorderSide(color: AppColors.border),
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: AppColors.dangerLight,
                child: Icon(Icons.person, color: AppColors.danger),
              ),
              title: Text(staff.name,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                'Tài khoản: ${staff.username}'
                '${staffStoreName.isNotEmpty ? ' • $staffStoreName' : ''}',
              ),
              trailing: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.dangerLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Chưa đến',
                  style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          );
        },
      );
    }

    // Filter records
    List<AttendanceRecord> records = state.allRecords;
    if (_selectedFilterIndex == 1) {
      records = state.workingStaff;
    } else if (_selectedFilterIndex == 2) {
      records = state.lateStaff;
    } else if (_selectedFilterIndex == 4) {
      records = state.checkedOutStaff;
    }

    if (records.isEmpty) {
      return const Center(
        child: Text('Không có bản ghi chấm công nào phù hợp bộ lọc.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: records.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final r = records[index];
        final inTimeStr =
            '${r.checkInTime.hour.toString().padLeft(2, '0')}:${r.checkInTime.minute.toString().padLeft(2, '0')}';
        final outTimeStr = r.checkOutTime != null
            ? '${r.checkOutTime!.hour.toString().padLeft(2, '0')}:${r.checkOutTime!.minute.toString().padLeft(2, '0')}'
            : 'Đang làm';

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
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 16,
                            backgroundColor: AppColors.primary.withOpacity(0.1),
                            child: Text(
                              r.userName.isNotEmpty
                                  ? r.userName[0].toUpperCase()
                                  : 'NV',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.userName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  r.shiftName,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    AttendanceStatusBadge(
                      status: r.status,
                      lateMinutes: r.lateMinutes,
                      earlyLeaveMinutes: r.earlyLeaveMinutes,
                      overtimeMinutes: r.overtimeMinutes,
                      isGpsValid: r.isGpsValid,
                      isWorking: r.isWorking,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  alignment: WrapAlignment.spaceBetween,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.login,
                            size: 16, color: AppColors.success),
                        const SizedBox(width: 4),
                        Text('Vào: $inTimeStr',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.logout,
                            size: 16, color: AppColors.danger),
                        const SizedBox(width: 4),
                        Text('Ra: $outTimeStr',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 16, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Text('Tổng: ${r.totalWorkHours}h',
                            style: const TextStyle(
                                fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
                if (r.explanationReason != null &&
                    r.explanationReason!.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Lý do giải trình: "${r.explanationReason}"',
                      style: const TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: AppColors.warningDeep),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
