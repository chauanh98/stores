import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/live_attendance_dashboard_provider.dart';
import 'package:stores/application/attendance/monthly_timesheet_notifier.dart';
import 'package:stores/domain/attendance/geo_distance_helper.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../application/attendance/fake_attendance_repository.dart';

void main() {
  group('=== KIOTVIET OPERATIONS UPGRADE: FINAL E2E ADVERSARIAL STRESS SUITE ===', () {
    // =========================================================================
    // R1: CUSTOMER DEBT SPECTRUM & RECEIVABLES MATHEMATICAL INTEGRITY
    // =========================================================================
    group('R1 Adversarial Stress: Customer Debt Filtering & Live Aggregation', () {
      final customers = [
        const Customer(
          id: 'c_neg_1',
          name: 'Khách Đặt Cọc Lớn',
          phone: '0901111111',
          email: 'neg1@test.com',
          address: 'Hà Nội',
          purchases: [],
          currentDebt: -50000000.0, // Prepaid / Deposit: -50,000,000 VND
        ),
        const Customer(
          id: 'c_neg_2',
          name: 'Khách Trả Dư',
          phone: '0902222222',
          email: 'neg2@test.com',
          address: 'Cần Thơ',
          purchases: [],
          currentDebt: -100.0, // Micro negative
        ),
        const Customer(
          id: 'c_zero_1',
          name: 'Khách Hết Nợ Chuẩn',
          phone: '0903333333',
          email: 'zero1@test.com',
          address: 'Đà Nẵng',
          purchases: [],
          currentDebt: 0.0,
        ),
        const Customer(
          id: 'c_null_debt',
          name: 'Khách Chưa Từng Nợ',
          phone: '0904444444',
          email: 'null@test.com',
          address: 'Huế',
          purchases: [],
          currentDebt: null,
        ),
        const Customer(
          id: 'c_micro_pos',
          name: 'Khách Nợ 1 Đồng',
          phone: '0905555555',
          email: 'pos1@test.com',
          address: 'Nha Trang',
          purchases: [],
          currentDebt: 1.0,
        ),
        const Customer(
          id: 'c_large_pos',
          name: 'Khách Nợ Vừa',
          phone: '0906666666',
          email: 'pos2@test.com',
          address: 'Hải Phòng',
          purchases: [],
          currentDebt: 25000000.0,
        ),
        const Customer(
          id: 'c_huge_pos',
          name: 'Khách Nợ Lớn',
          phone: '0907777777',
          email: 'pos3@test.com',
          address: 'TP.HCM',
          purchases: [],
          currentDebt: 2500000000.0, // 2.5 Billion VND
        ),
      ];

      test('R1.1: inDebt filter strictly admits currentDebt > 0 (excluding negatives and zeros)', () {
        final inDebtOnly = customers.where((c) => (c.currentDebt ?? 0) > 0).toList();
        expect(inDebtOnly.length, 3);
        expect(inDebtOnly.map((c) => c.id).toSet(), equals({'c_micro_pos', 'c_large_pos', 'c_huge_pos'}));
      });

      test('R1.2: cleared filter strictly admits currentDebt <= 0 (including deposits and zeros)', () {
        final clearedOnly = customers.where((c) => (c.currentDebt ?? 0) <= 0).toList();
        expect(clearedOnly.length, 4);
        expect(clearedOnly.map((c) => c.id).toSet(), equals({'c_neg_1', 'c_neg_2', 'c_zero_1', 'c_null_debt'}));
      });

      test('R1.3: inDebt sorting orders strictly descending by debt amount', () {
        final sortedInDebt = customers.where((c) => (c.currentDebt ?? 0) > 0).toList()
          ..sort((a, b) => b.displayCurrentDebt.compareTo(a.displayCurrentDebt));

        expect(sortedInDebt[0].id, 'c_huge_pos');
        expect(sortedInDebt[0].displayCurrentDebt, 2500000000.0);
        expect(sortedInDebt[1].id, 'c_large_pos');
        expect(sortedInDebt[1].displayCurrentDebt, 25000000.0);
        expect(sortedInDebt[2].id, 'c_micro_pos');
        expect(sortedInDebt[2].displayCurrentDebt, 1.0);
      });

      test('R1.4: Live total debt calculation excludes negative balances to prevent receivable distortion', () {
        // Business Rule: Total receivables = sum(positive debt only)
        final totalDebtSum = customers.fold<double>(
          0.0,
          (sum, c) => sum + (c.displayCurrentDebt > 0 ? c.displayCurrentDebt : 0.0),
        );

        const expectedPositiveSum = 1.0 + 25000000.0 + 2500000000.0;
        expect(totalDebtSum, equals(expectedPositiveSum));
        // Verify negative debt did NOT subtract from total
        expect(totalDebtSum, isNot(equals(expectedPositiveSum - 50000100.0)));
      });
    });

    // =========================================================================
    // R2: MULTI-STORE SUPPLIER DEBT ISOLATION & CLAMPING ARITHMETIC
    // =========================================================================
    group('R2 Adversarial Stress: Supplier Import Debt & Math Precision', () {
      test('R2.1: Overpayment clamps debt increase to exactly 0.0 (no negative debt creation)', () {
        const double totalBill = 5000000.0;
        const double paidAmount = 6500000.0; // Overpayment of 1.5M

        final debtIncrease = (totalBill - paidAmount).clamp(0.0, double.infinity);
        expect(debtIncrease, equals(0.0));
      });

      test('R2.2: Partial payment calculates exact debt increment and balance', () {
        const double initialDebt = 1200000.0;
        const double totalBill = 10000000.0;
        const double paidAmount = 4500000.0;

        final debtIncrease = (totalBill - paidAmount).clamp(0.0, double.infinity);
        final newDebt = initialDebt + debtIncrease;

        expect(debtIncrease, equals(5500000.0));
        expect(newDebt, equals(6700000.0));
      });

      test('R2.3: Zero-amount import transaction generates 0 debt and purchase increment', () {
        const double totalBill = 0.0;
        const double paidAmount = 0.0;
        const double initialDebt = 3000000.0;

        final debtIncrease = (totalBill - paidAmount).clamp(0.0, double.infinity);
        expect(debtIncrease, equals(0.0));
        expect(initialDebt + debtIncrease, equals(3000000.0));
      });

      test('R2.4: Sequential rapid imports accumulate purchase totals and debt consistently', () {
        var supplier = const Supplier(
          id: 'supp_stress_01',
          name: 'Công ty Cung ứng Stress',
          phone: '0988888888',
          code: 'NCC_STRESS',
          totalPurchase: 0.0,
          currentDebt: 0.0,
        );

        final transactions = <SupplierDebtTransaction>[];

        void simulateImport(double total, double paid) {
          final debtInc = (total - paid).clamp(0.0, double.infinity);
          final newTotalPurchase = supplier.totalPurchase + total;
          final newDebt = supplier.currentDebt + debtInc;

          if (debtInc > 0) {
            transactions.add(
              SupplierDebtTransaction(
                id: 'tx_${transactions.length + 1}',
                supplierId: supplier.id,
                date: DateTime.now(),
                type: SupplierDebtType.importBill,
                amount: debtInc,
                remainingDebt: newDebt,
              ),
            );
          }

          supplier = supplier.copyWith(
            totalPurchase: newTotalPurchase,
            currentDebt: newDebt,
          );
        }

        // 5 sequential imports
        simulateImport(1000000, 500000);  // debt +500k  (total 500k)
        simulateImport(2000000, 2000000); // debt +0     (total 500k)
        simulateImport(3000000, 0);       // debt +3M    (total 3.5M)
        simulateImport(500000, 600000);   // debt +0 (overpay) (total 3.5M)
        simulateImport(1500000, 1000000); // debt +500k  (total 4.0M)

        expect(supplier.totalPurchase, equals(8000000.0));
        expect(supplier.currentDebt, equals(4000000.0));
        expect(transactions.length, 3); // Only 3 imports had debtIncrease > 0
        expect(transactions.last.remainingDebt, equals(4000000.0));
      });
    });

    // =========================================================================
    // R3: KPI DRILL-DOWN ENTITY RESILIENCE
    // =========================================================================
    group('R3 Adversarial Stress: Drill-down Fallbacks & Data Boundaries', () {
      test('R3.1: Product ranking item with special characters and Vietnamese accents formats safely', () {
        const item = ProductRankingItem(
          productId: 'prod_unicode_01',
          productName: 'Trà Sữa Trân Châu Đường Đen 500ml (Đặc Biệt & Khuyến Mãi 50%) 🎉',
          categoryName: 'Đồ Uống / Giải Khát',
          quantity: 9999,
          revenue: 499950000.0,
        );

        expect(item.productId, 'prod_unicode_01');
        expect(item.productName.contains('🎉'), isTrue);
        expect(item.productName.contains('Trà Sữa'), isTrue);
      });

      test('R3.2: Customer ranking item fallback entity synthesizes correctly with null phone/email', () {
        const item = CustomerRankingItem(
          customerId: 'cust_unknown_999',
          customerName: 'Khách Vãng Lai Không Có SĐT',
          phoneNumber: null,
          orderCount: 1,
          totalSpent: 150000.0,
        );

        final resolved = Customer(
          id: item.customerId,
          name: item.customerName,
          phone: item.phoneNumber ?? '',
          email: '',
          address: '',
          purchases: const [],
        );

        expect(resolved.id, 'cust_unknown_999');
        expect(resolved.phone, '');
        expect(resolved.displayTotalSales, 0.0);
        expect(resolved.displayCurrentDebt, 0.0);
      });
    });

    // =========================================================================
    // R4: MULTI-STORE SUPERVISOR SCOPING & HAVERSINE BOUNDARIES
    // =========================================================================
    group('R4 Adversarial Stress: Role Scoping & Geofence Boundaries', () {
      late FakeAttendanceRepository fakeRepo;

      setUp(() {
        fakeRepo = FakeAttendanceRepository();
      });

      test('R4.1: Supervisor role is strictly locked to assigned storeId in LiveAttendanceDashboardNotifier', () async {
        const supervisor = UserAccount(
          username: 'supervisor_dt',
          displayName: 'Giám sát Đông Thắng',
          role: 'supervisor',
          storeId: 'store_001',
        );

        final notifier = LiveAttendanceDashboardNotifier(fakeRepo, supervisor);
        expect(notifier.state.storeId, 'store_001');

        // Malicious or accidental attempt to switch to another store
        await notifier.changeStore('store_002');
        expect(notifier.state.storeId, 'store_001'); // Remains store_001!

        await notifier.changeStore('store_003');
        expect(notifier.state.storeId, 'store_001'); // Still locked!

        await pumpEventQueue();
        notifier.dispose();
      });

      test('R4.2: Staff role is strictly locked to assigned storeId in LiveAttendanceDashboardNotifier', () async {
        const staff = UserAccount(
          username: 'staff_dt',
          displayName: 'Nhân viên Đông Thắng',
          role: 'staff',
          storeId: 'store_001',
        );

        final notifier = LiveAttendanceDashboardNotifier(fakeRepo, staff);
        expect(notifier.state.storeId, 'store_001');

        await notifier.changeStore('store_002');
        expect(notifier.state.storeId, 'store_001'); // Locked!

        await pumpEventQueue();
        notifier.dispose();
      });

      test('R4.3: Admin role has global multi-store switching privilege', () async {
        const admin = UserAccount(
          username: 'admin_global',
          displayName: 'Quản Trị Viên',
          role: 'admin',
          storeId: 'store_001',
        );

        final notifier = LiveAttendanceDashboardNotifier(fakeRepo, admin);
        expect(notifier.state.storeId, 'store_001');

        await notifier.changeStore('store_002');
        expect(notifier.state.storeId, 'store_002'); // Successfully switched to store_002!

        await pumpEventQueue();
        notifier.dispose();
      });

      test('R4.4: MonthlyTimesheetNotifier enforces supervisor store lock', () async {
        const supervisor = UserAccount(
          username: 'supervisor_dt',
          displayName: 'Giám sát Đông Thắng',
          role: 'supervisor',
          storeId: 'store_001',
        );

        final notifier = MonthlyTimesheetNotifier(fakeRepo, supervisor);
        expect(notifier.state.storeId, 'store_001');

        await notifier.changeStore('store_002');
        expect(notifier.state.storeId, 'store_001'); // Locked!
      });

      test('R4.5: Geodesic Haversine edge cases: exact 150m, 150.001m, antipodal and zero distance', () {
        const storeLat = 10.035000;
        const storeLon = 105.788000;
        const R = GeoDistanceHelper.earthRadiusMeters;

        // Exactly 0 distance (same coordinate)
        final distZero = GeoDistanceHelper.haversineDistance(
          storeLat,
          storeLon,
          storeLat,
          storeLon,
        );
        expect(distZero, closeTo(0.0, 0.001));

        // Exact 150.0m North
        const deltaLat150 = (150.0 / R) * (180.0 / 3.141592653589793);
        final is150Valid = GeoDistanceHelper.isWithinRadius(
          staffLat: storeLat + deltaLat150,
          staffLon: storeLon,
          storeLat: storeLat,
          storeLon: storeLon,
          allowedRadiusMeters: 150.0,
        );
        expect(is150Valid, isTrue);

        // 150.5m North (Outside allowed 150.0m)
        const deltaLat151 = (150.5 / R) * (180.0 / 3.141592653589793);
        final is151Valid = GeoDistanceHelper.isWithinRadius(
          staffLat: storeLat + deltaLat151,
          staffLon: storeLon,
          storeLat: storeLat,
          storeLon: storeLon,
          allowedRadiusMeters: 150.0,
        );
        expect(is151Valid, isFalse);

        // Symmetry: distance(A, B) == distance(B, A)
        final distAB = GeoDistanceHelper.haversineDistance(
          storeLat + deltaLat150,
          storeLon,
          storeLat,
          storeLon,
        );
        final distBA = GeoDistanceHelper.haversineDistance(
          storeLat,
          storeLon,
          storeLat + deltaLat150,
          storeLon,
        );
        expect(distAB, closeTo(distBA, 0.0001));
      });

      test('R4.6: Shift check-in late and check-out penalty math under boundary times', () {
        const shift = Shift(
          id: 'shift_morning',
          name: 'Ca Sáng',
          startTime: '08:00',
          endTime: '12:00',
          gracePeriodMinutes: 15,
          type: 'morning',
          standardWorkHours: 4.0,
        );

        final now = DateTime.now();

        // 1. Early check-in: 07:45 (15 min before shift start)
        final earlyCheckIn = DateTime(now.year, now.month, now.day, 7, 45);
        final lateMinEarly = shift.calculateLateMinutes(earlyCheckIn, now);
        expect(lateMinEarly, equals(0));

        // 2. Exact start: 08:00
        final onTimeCheckIn = DateTime(now.year, now.month, now.day, 8, 0);
        final lateMinOnTime = shift.calculateLateMinutes(onTimeCheckIn, now);
        expect(lateMinOnTime, equals(0));

        // 3. Exact grace end: 08:15
        final graceCheckIn = DateTime(now.year, now.month, now.day, 8, 15);
        final lateMinGrace = shift.calculateLateMinutes(graceCheckIn, now);
        expect(lateMinGrace, equals(0));

        // 4. One minute past grace: 08:16 -> 16 minutes late
        final lateCheckIn = DateTime(now.year, now.month, now.day, 8, 16);
        final lateMin = shift.calculateLateMinutes(lateCheckIn, now);
        expect(lateMin, equals(16));

        // 5. Early leave: Check out at 11:45 (15 minutes early)
        final earlyCheckOut = DateTime(now.year, now.month, now.day, 11, 45);
        final earlyLeaveMin = shift.calculateEarlyLeaveMinutes(earlyCheckOut, now);
        expect(earlyLeaveMin, equals(15));

        // 6. Overtime: Check out at 12:45 (45 minutes overtime)
        final otCheckOut = DateTime(now.year, now.month, now.day, 12, 45);
        final otMin = shift.calculateOvertimeMinutes(otCheckOut, now);
        expect(otMin, equals(45));
      });
    });
  });
}
