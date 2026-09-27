import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/attendance/shift.dart';

class ShiftSelectorCard extends StatelessWidget {
  final List<Shift> shifts;
  final Shift? selectedShift;
  final ValueChanged<Shift> onShiftSelected;
  final DateTime? currentTime;

  const ShiftSelectorCard({
    super.key,
    required this.shifts,
    required this.selectedShift,
    required this.onShiftSelected,
    this.currentTime,
  });

  @override
  Widget build(BuildContext context) {
    if (shifts.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: Text('Không có ca làm việc nào khả dụng.'),
        ),
      );
    }

    final evalTime = currentTime ?? DateTime.now();

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
            const Row(
              children: [
                Icon(Icons.schedule, size: 20, color: AppColors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chọn ca làm việc hôm nay',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: shifts.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final shift = shifts[index];
                final isSelected = selectedShift?.id == shift.id;
                final windowStatus = shift.getWindowStatus(evalTime, evalTime);

                return Opacity(
                  opacity: windowStatus == ShiftWindowStatus.open ? 1.0 : 0.6,
                  child: InkWell(
                    onTap: () => onShiftSelected(shift),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.surfaceHighlight
                            : AppColors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color:
                              isSelected ? AppColors.primary : AppColors.border,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            isSelected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.textSecondary,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        shift.name,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: isSelected
                                              ? AppColors.primaryDark
                                              : AppColors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: _buildStatusBadge(
                                          windowStatus, shift, evalTime),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${shift.startTime} - ${shift.endTime} (Chuẩn: ${shift.standardWorkHours}h, Ân hạn: ${shift.gracePeriodMinutes}p)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(
    ShiftWindowStatus status,
    Shift shift,
    DateTime evalTime,
  ) {
    final Color bgColor;
    final Color textColor;
    final Color borderColor;
    final String label;

    switch (status) {
      case ShiftWindowStatus.open:
        bgColor = AppColors.successLight;
        textColor = Colors.green.shade700;
        borderColor = AppColors.successBorder;
        label = 'Đang mở ca';
        break;
      case ShiftWindowStatus.closed:
        bgColor = AppColors.dangerLight;
        textColor = Colors.red.shade700;
        borderColor = AppColors.dangerBorder;
        label = 'Đã kết thúc';
        break;
      case ShiftWindowStatus.upcoming:
        final openTime = shift.getCheckInWindowStart(evalTime);
        final openTimeStr =
            '${openTime.hour.toString().padLeft(2, '0')}:${openTime.minute.toString().padLeft(2, '0')}';
        bgColor = AppColors.warningLight;
        textColor = Colors.orange.shade800;
        borderColor = AppColors.warningBorder;
        label = 'Chưa mở - Mở lúc $openTimeStr';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
