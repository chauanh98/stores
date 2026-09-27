import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../core/theme/app_colors.dart';

/// Sub-widget Bộ lọc thời gian và Chi nhánh trên Tab Tổng quan
/// Cung cấp Dropdown chọn khoảng thời gian (mở BottomSheet / DateRangePicker)
/// và Dropdown chọn lọc chi nhánh với BottomSheet picker.
class OverviewFilterBar extends ConsumerWidget {
  const OverviewFilterBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRange = ref.watch(overviewActiveDateRangeProvider);
    final timeRangeType = ref.watch(overviewTimeRangeTypeProvider);
    final selectedBranchIds = ref.watch(selectedBranchesProvider);
    final user = ref.watch(authProvider);
    final canSwitchStore = user?.canSwitchStore ?? false;
    final l10n = AppLocalizations.of(context);
    final currentStoreId = ref.watch(currentStoreIdProvider);
    final mockBranches = getMockBranches(currentStoreId);
    final storeFilter = ref.watch(selectedStoreFilterProvider);

    // Chuỗi nhãn hiển thị khoảng thời gian
    final String dateLabel;
    if (timeRangeType == OverviewTimeRange.custom) {
      dateLabel =
          '${DateFormat('dd/MM').format(activeRange.start)} - ${DateFormat('dd/MM').format(activeRange.end)}';
    } else {
      dateLabel = timeRangeType.label;
    }

    // Chuỗi nhãn hiển thị chi nhánh
    String branchLabel;
    if (storeFilter == 'all') {
      branchLabel = l10n?.allBranchesCombined ?? 'Tất cả chi nhánh';
    } else if (mockBranches.isNotEmpty &&
        selectedBranchIds.length == mockBranches.length) {
      branchLabel = l10n?.allBranches ?? 'Tất cả chi nhánh';
    } else if (selectedBranchIds.length == 1) {
      branchLabel = mockBranches
          .firstWhere(
            (b) => b.id == selectedBranchIds.first,
            orElse: () => mockBranches.isNotEmpty
                ? mockBranches.first
                : Branch(selectedBranchIds.first, selectedBranchIds.first),
          )
          .name;
    } else {
      branchLabel = '${selectedBranchIds.length} chi nhánh';
    }

    final isDefaultTimeRange = timeRangeType == OverviewTimeRange.today;
    final isAllBranches = selectedBranchIds.length == mockBranches.length;
    final hasActiveFilter = !isDefaultTimeRange ||
        !isAllBranches ||
        (storeFilter != null && storeFilter != 'all');

    return LayoutBuilder(
      builder: (context, constraints) {
        final isFinite = constraints.maxWidth.isFinite;
        final minRowWidth = isFinite
            ? (constraints.maxWidth - 32.0).clamp(0.0, double.infinity)
            : 0.0;
        return Container(
          color: AppColors.white,
          width: isFinite ? double.infinity : null,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            physics: const BouncingScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: minRowWidth),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Nút mở BottomSheet chọn thời gian
                      InkWell(
                        onTap: () => _showDateRangeBottomSheet(context, ref),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.primary.withOpacity(0.2),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.calendar_today_rounded,
                                size: 14,
                                color: AppColors.primary,
                              ),
                              const SizedBox(width: 6),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 130),
                                child: Text(
                                  dateLabel,
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                        ),
                      ),

                      if (hasActiveFilter) ...[
                        const SizedBox(width: 8),
                        InkWell(
                          key: const Key('reset_overview_filters_button'),
                          onTap: () => resetOverviewFilters(ref),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.danger.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: AppColors.danger.withOpacity(0.25),
                                width: 0.8,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 14,
                                  color: AppColors.danger,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Đặt lại',
                                  style: TextStyle(
                                    color: AppColors.danger,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),

                  // Nút mở BottomSheet chọn chi nhánh (nếu có quyền chuyển kho/chi nhánh)
                  Padding(
                    padding: const EdgeInsets.only(left: 8.0),
                    child: canSwitchStore
                        ? InkWell(
                            onTap: () =>
                                _showBranchFilterBottomSheet(context, ref),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.grey100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.grey300,
                                  width: 0.8,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.store_rounded,
                                    size: 15,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  ConstrainedBox(
                                    constraints:
                                        const BoxConstraints(maxWidth: 150),
                                    child: Text(
                                      branchLabel,
                                      style: const TextStyle(
                                        color: AppColors.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 18,
                                    color: AppColors.textSecondary,
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.store_rounded,
                                size: 14,
                                color: AppColors.textTertiary,
                              ),
                              const SizedBox(width: 4),
                              ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 150),
                                child: Text(
                                  branchLabel,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12,
                                  ),
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
          ),
        );
      },
    );
  }

  void _showDateRangeBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (consumerContext, sheetRef, _) {
            final activeType = sheetRef.watch(overviewTimeRangeTypeProvider);
            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Text(
                        'Chọn khoảng thời gian',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    ...OverviewTimeRange.values.map((type) {
                      final isSelected = activeType == type;
                      return ListTile(
                        dense: true,
                        title: Text(
                          type.label,
                          style: TextStyle(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textPrimary,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            fontSize: 14,
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle_rounded,
                                color: AppColors.primary, size: 20)
                            : null,
                        onTap: () async {
                          Navigator.pop(consumerContext);
                          if (type == OverviewTimeRange.custom) {
                            final initialRange =
                                ref.read(overviewCustomDateRangeProvider);
                            final now = DateTime.now();
                            final normalized = DateTimeRange(
                              start: DateTime(
                                initialRange.start.year,
                                initialRange.start.month,
                                initialRange.start.day,
                              ),
                              end: DateTime(
                                initialRange.end.year,
                                initialRange.end.month,
                                initialRange.end.day,
                              ),
                            );
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(
                                  now.year, now.month, now.day, 23, 59, 59),
                              initialDateRange: normalized,
                            );
                            if (picked != null) {
                              ref
                                  .read(
                                      overviewCustomDateRangeProvider.notifier)
                                  .state = picked;
                              ref
                                  .read(overviewTimeRangeTypeProvider.notifier)
                                  .state = OverviewTimeRange.custom;
                              persistOverviewFilters(
                                ref,
                                timeRangeType: OverviewTimeRange.custom,
                                customDateRange: picked,
                              );
                            }
                          } else {
                            ref
                                .read(overviewTimeRangeTypeProvider.notifier)
                                .state = type;
                            persistOverviewFilters(
                              ref,
                              timeRangeType: type,
                            );
                          }
                        },
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showBranchFilterBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (modalContext) {
        return Consumer(
          builder: (consumerContext, sheetRef, _) {
            final selectedBranchIds = sheetRef.watch(selectedBranchesProvider);
            final notifier = sheetRef.read(selectedBranchesProvider.notifier);
            final currentStoreId = sheetRef.watch(currentStoreIdProvider);
            final mockBranches = getMockBranches(currentStoreId);

            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Chọn chi nhánh lọc',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              notifier.selectAll();
                            },
                            child: const Text(
                              'Chọn tất cả',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: AppColors.divider),
                    ...mockBranches.map((branch) {
                      final isChecked = selectedBranchIds.contains(branch.id);
                      return CheckboxListTile(
                        dense: true,
                        title: Text(
                          branch.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        value: isChecked,
                        activeColor: AppColors.primary,
                        onChanged: (_) {
                          notifier.toggleBranch(branch.id);
                        },
                      );
                    }),
                    const SizedBox(height: 12),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.pop(modalContext),
                          style: FilledButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: const Text(
                            'Xong',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
