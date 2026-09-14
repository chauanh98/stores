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
    } else if (selectedBranchIds.length == mockBranches.length) {
      branchLabel = l10n?.allBranches ?? 'Tất cả chi nhánh';
    } else if (selectedBranchIds.length == 1) {
      branchLabel = mockBranches
          .firstWhere(
            (b) => b.id == selectedBranchIds.first,
            orElse: () => mockBranches.first,
          )
          .name;
    } else {
      branchLabel = '${selectedBranchIds.length} chi nhánh';
    }

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Nút mở BottomSheet chọn thời gian
          InkWell(
            onTap: () => _showDateRangeBottomSheet(context, ref),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                  Text(
                    dateLabel,
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
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

          // Nút mở BottomSheet chọn chi nhánh (nếu có quyền chuyển kho/chi nhánh)
          if (canSwitchStore)
            InkWell(
              onTap: () => _showBranchFilterBottomSheet(context, ref),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.grey.shade300,
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.store_rounded,
                      size: 15,
                      color: Colors.black54,
                    ),
                    const SizedBox(width: 6),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 150),
                      child: Text(
                        branchLabel,
                        style: const TextStyle(
                          color: Colors.black87,
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
                      color: Colors.black54,
                    ),
                  ],
                ),
              ),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.store_rounded,
                  size: 14,
                  color: Colors.black45,
                ),
                const SizedBox(width: 4),
                Text(
                  branchLabel,
                  style: const TextStyle(
                    color: Colors.black54,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _showDateRangeBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                          color: Colors.black87,
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
                            color:
                                isSelected ? AppColors.primary : Colors.black87,
                            fontWeight:
                                isSelected ? FontWeight.bold : FontWeight.normal,
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
                                  .read(overviewCustomDateRangeProvider.notifier)
                                  .state = picked;
                              ref
                                  .read(overviewTimeRangeTypeProvider.notifier)
                                  .state = OverviewTimeRange.custom;
                            }
                          } else {
                            ref
                                .read(overviewTimeRangeTypeProvider.notifier)
                                .state = type;
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
      backgroundColor: Colors.white,
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
                              color: Colors.black87,
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
