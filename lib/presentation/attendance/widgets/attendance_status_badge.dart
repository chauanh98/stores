import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/attendance/attendance_record.dart';

class AttendanceStatusBadge extends StatelessWidget {
  final AttendanceStatus status;
  final int lateMinutes;
  final int earlyLeaveMinutes;
  final int overtimeMinutes;
  final bool isGpsValid;
  final bool isWorking;

  const AttendanceStatusBadge({
    super.key,
    required this.status,
    this.lateMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.overtimeMinutes = 0,
    this.isGpsValid = true,
    this.isWorking = false,
  });

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    IconData icon;

    if (isWorking) {
      bg = AppColors.primary.withOpacity(0.12);
      fg = AppColors.primary;
      label = 'Đang làm việc';
      icon = Icons.access_time_filled;
    } else {
      switch (status) {
        case AttendanceStatus.onTime:
          bg = AppColors.attendanceOnTimeBg;
          fg = AppColors.attendanceOnTimeText;
          label = 'Đúng giờ';
          icon = Icons.check_circle_outline;
          break;
        case AttendanceStatus.late:
          bg = AppColors.attendanceLateBg;
          fg = AppColors.attendanceLateText;
          label = lateMinutes > 0 ? 'Muộn $lateMinutes phút' : 'Đi muộn';
          icon = Icons.warning_amber_rounded;
          break;
        case AttendanceStatus.earlyLeave:
          bg = AppColors.attendanceEarlyLeaveBg;
          fg = AppColors.attendanceEarlyLeaveText;
          label = earlyLeaveMinutes > 0
              ? 'Về sớm $earlyLeaveMinutes phút'
              : 'Về sớm';
          icon = Icons.directions_walk;
          break;
        case AttendanceStatus.overtime:
          bg = AppColors.supervisorLight;
          fg = AppColors.supervisor;
          label =
              overtimeMinutes > 0 ? 'Tăng ca $overtimeMinutes phút' : 'Tăng ca';
          icon = Icons.more_time;
          break;
      }
    }

    return Wrap(
      spacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: fg,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (!isGpsValid)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.dangerLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.location_off, size: 14, color: AppColors.danger),
                SizedBox(width: 4),
                Flexible(
                  child: Text(
                    'GPS ngoài bán kính',
                    style: TextStyle(
                      color: AppColors.danger,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
