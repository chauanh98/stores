import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../domain/attendance/attendance_adjustment.dart';
import '../../../domain/attendance/attendance_record.dart';

/// Dialog for staff to submit an attendance adjustment request.
class RequestAdjustmentDialog extends StatefulWidget {
  final AttendanceRecord? initialRecord;
  final String userId;
  final String userName;
  final String storeId;
  final Function(AttendanceAdjustment) onSubmit;

  const RequestAdjustmentDialog({
    super.key,
    this.initialRecord,
    required this.userId,
    required this.userName,
    required this.storeId,
    required this.onSubmit,
  });

  @override
  State<RequestAdjustmentDialog> createState() => _RequestAdjustmentDialogState();
}

class _RequestAdjustmentDialogState extends State<RequestAdjustmentDialog> {
  late DateTime _selectedDate;
  late TimeOfDay _inTime;
  late TimeOfDay _outTime;
  final _reasonController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialRecord?.date ?? DateTime.now();
    final checkIn = widget.initialRecord?.checkInTime ?? DateTime.now();
    final checkOut = widget.initialRecord?.checkOutTime ??
        widget.initialRecord?.checkInTime.add(const Duration(hours: 4)) ??
        DateTime.now().add(const Duration(hours: 4));

    _inTime = TimeOfDay(hour: checkIn.hour, minute: checkIn.minute);
    _outTime = TimeOfDay(hour: checkOut.hour, minute: checkOut.minute);
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.edit_calendar, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Yêu cầu điều chỉnh công', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gửi giải trình / điều chỉnh giờ vào, giờ ra cho quản lý duyệt:',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today, color: AppColors.primary, size: 20),
              title: const Text('Ngày chấm công:'),
              subtitle: Text(
                '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: TextButton(
                child: const Text('Chọn'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2025),
                    lastDate: DateTime(2030),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
              ),
            ),
            const Divider(height: 1),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.login, color: AppColors.success, size: 20),
              title: const Text('Giờ vào mong muốn:'),
              subtitle: Text(
                '${_inTime.hour.toString().padLeft(2, '0')}:${_inTime.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: TextButton(
                child: const Text('Đổi'),
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: _inTime);
                  if (picked != null) setState(() => _inTime = picked);
                },
              ),
            ),
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.logout, color: AppColors.danger, size: 20),
              title: const Text('Giờ ra mong muốn:'),
              subtitle: Text(
                '${_outTime.hour.toString().padLeft(2, '0')}:${_outTime.minute.toString().padLeft(2, '0')}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              trailing: TextButton(
                child: const Text('Đổi'),
                onPressed: () async {
                  final picked = await showTimePicker(context: context, initialTime: _outTime);
                  if (picked != null) setState(() => _outTime = picked);
                },
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _reasonController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Lý do giải trình (*)',
                hintText: 'Nhập lý do chi tiết (quên chấm công, lỗi mạng, đi giao hàng...)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Hủy'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final reason = _reasonController.text.trim();
            if (reason.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Vui lòng nhập lý do giải trình.')),
              );
              return;
            }

            final reqIn = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              _inTime.hour,
              _inTime.minute,
            );
            final reqOut = DateTime(
              _selectedDate.year,
              _selectedDate.month,
              _selectedDate.day,
              _outTime.hour,
              _outTime.minute,
            );

            final adjustment = AttendanceAdjustment(
              id: 'adj_${DateTime.now().millisecondsSinceEpoch}',
              attendanceId: widget.initialRecord?.id ?? '',
              userId: widget.userId,
              userName: widget.userName,
              storeId: widget.storeId,
              requestedCheckIn: reqIn,
              requestedCheckOut: reqOut,
              reason: reason,
              status: AdjustmentStatus.pending,
              submittedAt: DateTime.now(),
            );

            widget.onSubmit(adjustment);
            Navigator.of(context).pop();
          },
          child: const Text('Gửi yêu cầu'),
        ),
      ],
    );
  }
}

/// Dialog for Admin/Supervisor to review and approve/reject an adjustment.
class ReviewAdjustmentDialog extends StatefulWidget {
  final AttendanceAdjustment adjustment;
  final Function(String note) onApprove;
  final Function(String note) onReject;

  const ReviewAdjustmentDialog({
    super.key,
    required this.adjustment,
    required this.onApprove,
    required this.onReject,
  });

  @override
  State<ReviewAdjustmentDialog> createState() => _ReviewAdjustmentDialogState();
}

class _ReviewAdjustmentDialogState extends State<ReviewAdjustmentDialog> {
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final adj = widget.adjustment;
    final inStr = '${adj.requestedCheckIn.hour.toString().padLeft(2, '0')}:${adj.requestedCheckIn.minute.toString().padLeft(2, '0')}';
    final outStr = '${adj.requestedCheckOut.hour.toString().padLeft(2, '0')}:${adj.requestedCheckOut.minute.toString().padLeft(2, '0')}';

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.approval, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Xét duyệt giải trình công', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nhân viên: ${adj.userName} (${adj.userId})', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Thời gian xin điều chỉnh: $inStr - $outStr'),
            const SizedBox(height: 6),
            Text('Lý do nhân viên: "${adj.reason}"', style: const TextStyle(fontStyle: FontStyle.italic, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Ghi chú phê duyệt / từ chối',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Đóng'),
        ),
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.danger,
            side: const BorderSide(color: AppColors.danger),
          ),
          onPressed: () {
            widget.onReject(_noteController.text.trim());
            Navigator.of(context).pop();
          },
          child: const Text('Từ chối'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            widget.onApprove(_noteController.text.trim());
            Navigator.of(context).pop();
          },
          child: const Text('Duyệt công'),
        ),
      ],
    );
  }
}
