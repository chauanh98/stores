import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/attendance/attendance_adjustment.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/presentation/attendance/widgets/adjustment_dialog.dart';
import 'package:stores/presentation/attendance/widgets/shift_selector_card.dart';
import 'package:stores/presentation/products/widgets/category_filter_bottom_sheet.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';
import 'package:stores/presentation/reports/widgets/quick_actions_bar.dart';

import 'sweep_harness.dart';

/// Opens [open] right after the first frame so dialogs / sheets get their real
/// route constraints (instead of being laid out as plain body widgets).
class _Opener extends StatefulWidget {
  const _Opener(this.open);
  final Future<void> Function(BuildContext) open;
  @override
  State<_Opener> createState() => _OpenerState();
}

class _OpenerState extends State<_Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => widget.open(context));
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox());
}

List<Override> _ov(user) => [
      authProvider.overrideWith((ref) => SweepAuth(user)),
      currentStoreIdProvider.overrideWithValue('store_001'),
      productListProvider
          .overrideWith((ref) => Stream.value(sweepProducts(80))),
      categoryListProvider.overrideWith((ref) => Stream.value([
            for (var i = 0; i < 120; i++)
              Category(
                  id: 'c$i',
                  name: i % 4 == 0
                      ? 'Bia, Rượu, Nước giải khát nhập khẩu rất dài $i'
                      : 'Nhóm $i',
                  parentId: i % 4 == 0 || i < 4 ? null : 'c${(i ~/ 4) * 4}')
          ])),
    ];

void main() {
  final now = DateTime.now();
  final record = AttendanceRecord(
    id: 'a',
    userId: 'u',
    userName: 'Nguyễn Thị Thanh Thảo Hoàng Gia Bảo Châu',
    storeId: 'store_001',
    shiftId: 'shift_morning',
    shiftName: 'Ca làm việc có tên rất dài để kiểm tra tràn dòng',
    date: now,
    checkInTime: DateTime(now.year, now.month, now.day, 8),
    checkOutTime: DateTime(now.year, now.month, now.day, 12),
    checkInGpsLat: 10,
    checkInGpsLng: 105,
    isGpsValid: true,
  );

  sweepMatrix(
      'CategoryFilterBottomSheet(120 cats)',
      () => _Opener((c) => CategoryFilterBottomSheet.show(c,
          currentCategory: 'Tất cả', onSelected: (_) {})),
      _ov);
  sweepMatrix(
      'RequestAdjustmentDialog',
      () => _Opener((c) => showDialog(
          context: c,
          builder: (_) => RequestAdjustmentDialog(
              initialRecord: record,
              userId: 'u',
              userName: 'Nguyễn Thị Thanh Thảo Hoàng Gia Bảo Châu',
              storeId: 'store_001',
              onSubmit: (_) {}))),
      _ov);
  sweepMatrix(
      'ReviewAdjustmentDialog',
      () => _Opener((c) => showDialog(
          context: c,
          builder: (_) => ReviewAdjustmentDialog(
              adjustment: AttendanceAdjustment(
                id: 'x',
                attendanceId: 'a',
                userId: 'u',
                userName: 'Nguyễn Thị Thanh Thảo Hoàng Gia Bảo Châu',
                storeId: 'store_001',
                requestedCheckIn: DateTime(now.year, now.month, now.day, 8),
                requestedCheckOut: DateTime(now.year, now.month, now.day, 12),
                reason: 'Lý do rất dài ' * 20,
              ),
              onApprove: (_) {},
              onReject: (_) {}))),
      _ov);
  sweepMatrix(
      'ShiftSelectorCard',
      () => Scaffold(
              body: SingleChildScrollView(
            child: ShiftSelectorCard(
              shifts: [
                ...Shift.defaultShifts(),
                for (var i = 0; i < 6; i++)
                  Shift(
                      id: 's$i',
                      name:
                          'Ca làm việc có tên rất dài để kiểm tra tràn dòng $i',
                      startTime: '00:00',
                      endTime: '23:59',
                      type: 'flexible'),
              ],
              selectedShift: null,
              onShiftSelected: (_) {},
            ),
          )),
      _ov);
  sweepMatrix(
      'QuickActionsBar', () => const Scaffold(body: QuickActionsBar()), _ov);
  sweepMatrix(
      'ProductTile(huge)',
      () => Scaffold(
              body: SingleChildScrollView(
                  child: Column(children: [
            for (final p in sweepProducts(4)) ProductTile(product: p),
          ]))),
      _ov);
}
