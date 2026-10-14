import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventories/stock_transfer_providers.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/revenue_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/attendance/attendance_adjustment.dart';
import 'package:stores/domain/attendance/attendance_record.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/main.dart';
import 'package:stores/presentation/attendance/pages/attendance_check_in_page.dart';
import 'package:stores/presentation/attendance/pages/live_attendance_dashboard_page.dart';
import 'package:stores/presentation/attendance/pages/monthly_timesheet_page.dart';
import 'package:stores/presentation/attendance/pages/shift_config_page.dart';
import 'package:stores/presentation/auth/pages/login_page.dart';
import 'package:stores/presentation/settings/pages/account_management_page.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';
import 'package:stores/presentation/settings/pages/store_payment_settings_page.dart';

import '../../application/attendance/fake_attendance_repository.dart';
import 'stress_kit.dart';

final _g = Gen();

class _Customers extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

class _Suppliers extends SupplierListNotifier {
  @override
  Future<List<Supplier>> build() async => [];
}

final _accounts = _g.accounts(2000);

final _config = StorePaymentConfig(
  storeId: 'store_001',
  storeName: '$longWord $emojiStr',
  address: '$newlines $rtl',
  phone: '0917.865 300',
  bankName: 'VIETINBANK',
  bankId: 'vietinbank',
  accountNo: '0917865300123456789',
  accountName: combining * 4,
  footerNote: longWord,
  paperSize: 'k80',
  showVietQR: true,
);

FakeAttendanceRepository _repo(int employees) {
  final now = DateTime.now();
  final dim = DateTime(now.year, now.month + 1, 0).day;
  final repo = FakeAttendanceRepository();
  repo.shifts = [
    ...Shift.defaultShifts(),
    Shift(
        id: 'shift_long',
        name: longWord,
        startTime: '00:00',
        endTime: '23:59',
        type: 'flexible'),
  ];
  for (var e = 0; e < employees; e++) {
    for (var d = 1; d <= dim; d++) {
      final r = _g.r;
      if (r.nextInt(5) == 0) continue;
      final uid = e == 0 ? 's' : 'staff_$e';
      repo.attendances.add(AttendanceRecord(
        id: 'att_${e}_$d',
        userId: uid,
        userName: _g.maybeAdv('Nhân viên $e', p: .3),
        storeId: 'store_001',
        shiftId: e.isEven ? 'shift_morning' : 'shift_long',
        shiftName: _g.adv(),
        date: DateTime(now.year, now.month, d),
        checkInTime: DateTime(now.year, now.month, d, 8, r.nextInt(60)),
        checkOutTime: r.nextInt(4) == 0
            ? null
            : DateTime(now.year, now.month, d, 12 + r.nextInt(8)),
        checkInGpsLat: 10.035,
        checkInGpsLng: 105.788,
        isGpsValid: r.nextInt(4) != 0,
        status:
            AttendanceStatus.values[r.nextInt(AttendanceStatus.values.length)],
        lateMinutes: r.nextInt(2000),
        totalWorkHours: r.nextInt(24) * 1.0,
        explanationReason: r.nextBool() ? _g.adv() : null,
      ));
    }
  }
  repo.adjustments.add(AttendanceAdjustment(
    id: 'adj',
    attendanceId: 'att_0_1',
    userId: 's',
    userName: longWord,
    storeId: 'store_001',
    requestedCheckIn: DateTime(now.year, now.month, 1, 8),
    requestedCheckOut: DateTime(now.year, now.month, 1, 12, 30),
    reason: '$newlines$longWord$emojiStr',
    status: AdjustmentStatus.pending,
    submittedAt: now,
  ));
  return repo;
}

final _bigRepo = _repo(100);

List<Override> ov(UserAccount user,
    {int accounts = 2000, bool error = false, FakeAttendanceRepository? repo}) {
  final products = _g.products(300);
  return [
    authProvider.overrideWith((ref) => SweepAuth(user)),
    currentStoreIdProvider.overrideWithValue('store_001'),
    currentStoreNameProvider.overrideWith((ref) async => sweepLongStore),
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': sweepLongStore,
          'store_002': 'Chi nhánh Thới Bình',
          'store_003': emojiStr,
        }),
    attendanceRepositoryProvider.overrideWithValue(repo ?? _bigRepo),
    shiftRepositoryProvider.overrideWithValue(repo ?? _bigRepo),
    locationServiceProvider.overrideWithValue(FakeLocationService()),
    allBranchesOrdersByDateRangeProvider
        .overrideWith((ref, range) => Stream.value(<Order>[])),
    allBranchesReturnOrdersByDateRangeProvider
        .overrideWith((ref, r) => Stream.value([])),
    posDraftOrdersProvider.overrideWith((ref) => Stream.value(<Order>[])),
    customerListNotifierProvider.overrideWith(() => _Customers()),
    supplierListNotifierProvider.overrideWith(() => _Suppliers()),
    productListProvider.overrideWith((ref) => Stream.value(products)),
    allStoresProductsProvider.overrideWith((ref) => Stream.value(products)),
    categoryListProvider.overrideWith((ref) => Stream.value(<Category>[])),
    notificationStreamProvider
        .overrideWith((ref) => Stream.value(<NotificationItem>[])),
    popupNotificationStreamProvider
        .overrideWith((ref) => Stream.value(<NotificationItem>[])),
    pendingIncomingTransferCountProvider
        .overrideWith((ref) => Stream.value(1234567)),
    accountsListProvider.overrideWith((ref) => error
        ? Stream<List<UserAccount>>.error('boom')
        : Stream.value(_accounts.take(accounts).toList())),
    storePaymentConfigProvider.overrideWithValue(_config),
    revenueByDateRangeProvider.overrideWith((ref, r) =>
        Stream.value(_g.revenue(30, mode: 'normal', start: r.start))),
    overviewKPIsProvider
        .overrideWith((ref) => const AsyncValue.data(OverviewKPIs.empty)),
  ];
}

void main() {
  // ---------------------------------------------------------- settings
  stressMatrix('MorePage', () => const MorePage(), (u) => ov(u));
  stressMatrix(
      'MorePage(empty username)',
      () => const MorePage(),
      (u) => [
            ...ov(u),
            authProvider.overrideWith((ref) => SweepAuth(UserAccount(
                username: '',
                displayName: '',
                role: u.role,
                storeId: 'store_001'))),
          ],
      rot: 2);
  stressMatrix('AccountManagementPage(2000)',
      () => const AccountManagementPage(), (u) => ov(u), rot: 1,
      check: (t, d) async {
    final n = find.byType(ListTile, skipOffstage: false).evaluate().length;
    expect(n, lessThan(120), reason: 'built $n tiles of 2000');
    if (find.byType(Scrollable).evaluate().isNotEmpty) {
      await t.fling(
          find.byType(Scrollable).first, const Offset(0, -5000), 6000);
      await t.pumpAndSettle();
    }
  });
  stressMatrix('AccountManagementPage(empty)',
      () => const AccountManagementPage(), (u) => ov(u, accounts: 0),
      rot: 3);
  stressMatrix('AccountManagementPage(error)',
      () => const AccountManagementPage(), (u) => ov(u, error: true),
      rot: 4);
  stressMatrix('StorePaymentSettingsPage',
      () => const StorePaymentSettingsPage(), (u) => ov(u),
      rot: 2);

  // -------------------------------------------------------- attendance
  stressMatrix('AttendanceCheckInPage', () => const AttendanceCheckInPage(),
      (u) => ov(u),
      rot: 1);
  stressMatrix('LiveAttendanceDashboardPage(3100 recs)',
      () => const LiveAttendanceDashboardPage(), (u) => ov(u),
      rot: 2, maxMs: 4000);
  stressMatrix('LiveAttendanceDashboardPage(empty)',
      () => const LiveAttendanceDashboardPage(), (u) => ov(u, repo: _repo(0)),
      rot: 4);
  stressMatrix('MonthlyTimesheetPage(all, 100x31)',
      () => const MonthlyTimesheetPage(), (u) => ov(u),
      rot: 3, maxMs: 4000);
  stressMatrix('MonthlyTimesheetPage(personal)',
      () => const MonthlyTimesheetPage(isPersonalOnly: true), (u) => ov(u),
      rot: 1);
  stressMatrix('MonthlyTimesheetPage(empty)',
      () => const MonthlyTimesheetPage(), (u) => ov(u, repo: _repo(0)),
      rot: 0);
  stressMatrix('ShiftConfigPage', () => const ShiftConfigPage(), (u) => ov(u),
      rot: 2);

  // ------------------------------------------------------------- auth
  stressMatrix('LoginPage', () => const LoginPage(), (u) => []);

  // -------------------------------------------------------------- shell
  for (var i = 0; i < devices.length; i++) {
    final d = devices[i];
    final scale = textScales[i % textScales.length];
    final u = i.isEven ? sweepAdmin : sweepStaff;
    testWidgets('AdaptiveScaffold shell @${d.name} x$scale ${u.role}',
        (t) async {
      setDevice(t, d);
      debugErrors();
      addTearDown(t.view.reset);
      await t.pumpWidget(
          stressHost(const AdaptiveScaffold(), ov(u), textScale: scale));
      await t.pump(const Duration(milliseconds: 600));
      expectClean(t, 'shell initial ${d.name}');
      final wide = d.w > 600;
      final bar = find.byType(wide ? NavigationRail : NavigationBar);
      expect(bar, findsOneWidget);
      for (final icon in [
        Icons.inventory_2_outlined,
        Icons.storefront_outlined,
        Icons.receipt_long_outlined,
        Icons.menu,
        Icons.trending_up,
      ]) {
        final f = find.descendant(of: bar, matching: find.byIcon(icon));
        if (f.evaluate().isEmpty) continue; // selected variant swaps the icon
        await t.tap(f.first);
        await t.pump(const Duration(milliseconds: 600));
        expectClean(t, 'shell tab $icon ${d.name} x$scale');
      }
      // rotate/resize while on the last tab
      t.view.physicalSize = Size(d.h * d.dpr, d.w * d.dpr);
      await t.pump(const Duration(milliseconds: 400));
      expectClean(t, 'shell rotate ${d.name}');
    });
  }
}
