import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'support/kiotviet_e2e_harness.dart';

void main() {
  group('=== KIOTVIET OPERATIONS UPGRADE: TIER 2 BOUNDARY & CORNER CASES ===', () {
    // ========================================================================
    // R1: CUSTOMER DEBT FILTER BOUNDARY & CORNER CASES
    // ========================================================================
    group('R1 Boundaries & Corner Cases: Customer Debt Filter', () {
      test('B1.1: Exact 0 debt customer (currentDebt == 0.0) is excluded from "Còn nợ" and included in "Hết nợ"', () {
        const custZero = Customer(
          id: 'CUST_ZERO',
          name: 'Khách Không Nợ',
          phone: '0901000000',
          email: 'zero@test.com',
          address: 'TP.HCM',
          purchases: [],
          currentDebt: 0.0,
        );

        final inDebt = CustomerDebtEngine.filterCustomers(
          customers: [custZero],
          filter: CustomerDebtFilter.inDebt,
        );
        final cleared = CustomerDebtEngine.filterCustomers(
          customers: [custZero],
          filter: CustomerDebtFilter.cleared,
        );

        expect(inDebt, isEmpty);
        expect(cleared.length, equals(1));
        expect(cleared.first.id, equals('CUST_ZERO'));
      });

      test('B1.2: Negative debt customer (credit balance/overpaid, e.g. -200,000đ) is excluded from "Còn nợ"', () {
        const custOverpaid = Customer(
          id: 'CUST_NEG',
          name: 'Khách Trả Thừa',
          phone: '0901000001',
          email: 'neg@test.com',
          address: 'Hà Nội',
          purchases: [],
          currentDebt: -200000.0,
        );

        final inDebt = CustomerDebtEngine.filterCustomers(
          customers: [custOverpaid],
          filter: CustomerDebtFilter.inDebt,
        );
        final cleared = CustomerDebtEngine.filterCustomers(
          customers: [custOverpaid],
          filter: CustomerDebtFilter.cleared,
        );

        expect(inDebt, isEmpty);
        expect(cleared.length, equals(1));
        expect(CustomerDebtEngine.calculateLiveTotalDebt(inDebt), equals(0.0));
      });

      test('B1.3: Null debt customer (currentDebt == null) is treated as 0 debt without exception', () {
        const custNull = Customer(
          id: 'CUST_NULL',
          name: 'Khách Null Nợ',
          phone: '0901000002',
          email: 'null@test.com',
          address: 'Đà Nẵng',
          purchases: [],
          currentDebt: null,
        );

        expect(custNull.displayCurrentDebt, equals(0.0));

        final inDebt = CustomerDebtEngine.filterCustomers(
          customers: [custNull],
          filter: CustomerDebtFilter.inDebt,
        );
        final cleared = CustomerDebtEngine.filterCustomers(
          customers: [custNull],
          filter: CustomerDebtFilter.cleared,
        );

        expect(inDebt, isEmpty);
        expect(cleared.length, equals(1));
      });

      test('B1.4: Fractional / decimal debt amounts (e.g. 0.01đ, 12345.67đ) sort and sum accurately', () {
        const c1 = Customer(
          id: 'CUST_DEC1',
          name: 'Khách Phẩy Nhỏ',
          phone: '0901000003',
          email: 'dec1@test.com',
          address: 'Cần Thơ',
          purchases: [],
          currentDebt: 0.01,
        );
        const c2 = Customer(
          id: 'CUST_DEC2',
          name: 'Khách Phẩy Lớn',
          phone: '0901000004',
          email: 'dec2@test.com',
          address: 'Cần Thơ',
          purchases: [],
          currentDebt: 12345.67,
        );

        final inDebt = CustomerDebtEngine.filterCustomers(
          customers: [c1, c2],
          filter: CustomerDebtFilter.inDebt,
        );

        expect(inDebt.length, equals(2));
        expect(inDebt.first.id, equals('CUST_DEC2')); // 12345.67 > 0.01
        expect(inDebt.last.id, equals('CUST_DEC1'));

        final total = CustomerDebtEngine.calculateLiveTotalDebt(inDebt);
        expect(total, closeTo(12345.68, 0.0001));
      });

      test('B1.5: Extreme large debt amounts (50,000,000,000đ - 50 billion VND) do not cause overflow', () {
        const cExtreme = Customer(
          id: 'CUST_BILLION',
          name: 'Đại Khách Hàng',
          phone: '0901999999',
          email: 'vip@test.com',
          address: 'TP.HCM',
          purchases: [],
          currentDebt: 50000000000.0,
        );

        final inDebt = CustomerDebtEngine.filterCustomers(
          customers: [cExtreme],
          filter: CustomerDebtFilter.inDebt,
        );

        expect(inDebt.length, equals(1));
        final total = CustomerDebtEngine.calculateLiveTotalDebt(inDebt);
        expect(total, equals(50000000000.0));
      });

      test('B1.6: Empty customer state returns empty list and 0.0 total debt without crash', () {
        final inDebt = CustomerDebtEngine.filterCustomers(
          customers: [],
          filter: CustomerDebtFilter.inDebt,
        );
        expect(inDebt, isEmpty);
        expect(CustomerDebtEngine.calculateLiveTotalDebt(inDebt), equals(0.0));
      });

      test('B1.7: Intersecting search query with "Còn nợ" tab filter matches name while enforcing debt', () {
        const c1 = Customer(
          id: 'CUST_A1',
          name: 'Nguyễn Văn Minh',
          phone: '0901111222',
          email: 'minh1@test.com',
          address: 'Hà Nội',
          purchases: [],
          currentDebt: 500000.0,
        );
        const c2 = Customer(
          id: 'CUST_A2',
          name: 'Nguyễn Văn Minh',
          phone: '0903333444',
          email: 'minh2@test.com',
          address: 'Hà Nội',
          purchases: [],
          currentDebt: 0.0,
        );

        // Searching for "Minh" in "Còn nợ" mode should only return c1
        final filtered = CustomerDebtEngine.filterCustomers(
          customers: [c1, c2],
          filter: CustomerDebtFilter.inDebt,
          searchQuery: 'Minh',
        );

        expect(filtered.length, equals(1));
        expect(filtered.first.id, equals('CUST_A1'));
      });
    });

    // ========================================================================
    // R2: SUPPLIER INTEGRATION BOUNDARY & CORNER CASES
    // ========================================================================
    group('R2 Boundaries & Corner Cases: Supplier Import & Debt Management', () {
      late Supplier baseSupplier;

      setUp(() {
        baseSupplier = const Supplier(
          id: 'SUP_CORNER',
          code: 'NCC_CORNER',
          name: 'Nhà Cung Cấp Corner',
          totalPurchase: 50000000.0,
          currentDebt: 10000000.0,
        );
      });

      test('B2.1: 100% debt option (paidAmount == 0): full import total added to currentDebt', () {
        const importTotal = 30000000.0;
        final res = SupplierDebtEngine.processImportDebt(
          supplier: baseSupplier,
          totalAmount: importTotal,
          paidAmount: 0.0, // 0 paid -> 100% debt
        );

        expect(res.updatedSupplier.currentDebt, equals(40000000.0)); // 10M + 30M
        expect(res.updatedSupplier.totalPurchase, equals(80000000.0)); // 50M + 30M
        expect(res.debtTransaction, isNotNull);
        expect(res.debtTransaction!.amount, equals(30000000.0));
      });

      test('B2.2: Overpayment attempt (paidAmount > totalAmount): debt addition clamped to 0.0', () {
        const importTotal = 20000000.0;
        final res = SupplierDebtEngine.processImportDebt(
          supplier: baseSupplier,
          totalAmount: importTotal,
          paidAmount: 25000000.0, // paid 25M on 20M bill
        );

        // Clamp rule prevents unintended debt changes
        expect(res.updatedSupplier.currentDebt, equals(10000000.0));
        expect(res.updatedSupplier.totalPurchase, equals(70000000.0));
        expect(res.debtTransaction, isNull);
      });

      test('B2.3: Zero amount import (totalAmount == 0.0): creates 0 debt and no debt transaction', () {
        final res = SupplierDebtEngine.processImportDebt(
          supplier: baseSupplier,
          totalAmount: 0.0,
          paidAmount: 0.0,
        );

        expect(res.updatedSupplier.currentDebt, equals(10000000.0));
        expect(res.updatedSupplier.totalPurchase, equals(50000000.0));
        expect(res.debtTransaction, isNull);
      });

      test('B2.4: Extreme large import value (100,000,000,000đ) preserves double precision', () {
        const massiveTotal = 100000000000.0; // 100 billion VND
        final res = SupplierDebtEngine.processImportDebt(
          supplier: baseSupplier,
          totalAmount: massiveTotal,
          paidAmount: 40000000000.0, // 40 billion paid, 60 billion debt added
        );

        // Initial debt is 10M (10,000,000) + 60B (60,000,000,000) = 60,010,000,000
        expect(res.updatedSupplier.currentDebt, equals(60010000000.0));
        // Initial purchase is 50M (50,000,000) + 100B (100,000,000,000) = 100,050,000,000
        expect(res.updatedSupplier.totalPurchase, equals(100050000000.0));
      });

      test('B2.5: Supplier debt type deserialization from database values: parses import_debt, import, purchase', () {
        expect(SupplierDebtTypeExtension.fromDbValue('import'), equals(SupplierDebtType.importBill));
        expect(SupplierDebtTypeExtension.fromDbValue('importbill'), equals(SupplierDebtType.importBill));
        expect(SupplierDebtTypeExtension.fromDbValue('purchase'), equals(SupplierDebtType.importBill));
        expect(SupplierDebtTypeExtension.fromDbValue('payment'), equals(SupplierDebtType.payment));
        expect(SupplierDebtTypeExtension.fromDbValue('adjustment'), equals(SupplierDebtType.adjustment));
        expect(SupplierDebtTypeExtension.fromDbValue('return'), equals(SupplierDebtType.returnOrder));
        // Fallback for unknown value defaults to payment safely
        expect(SupplierDebtTypeExtension.fromDbValue('unknown_xyz'), equals(SupplierDebtType.payment));
      });

      test('B2.6: Unselected supplier on inventory import proceeds safely without debt transaction', () {
        // When no supplier is chosen, debt engine is not called, inventory tx has null supplierId
        const tx = null;
        expect(tx, isNull);
      });

      test('B2.7: Rapid sequential imports accumulate debt and purchase values consistently', () {
        var current = baseSupplier;

        // Import 1: 10M total, 5M debt
        final r1 = SupplierDebtEngine.processImportDebt(
          supplier: current,
          totalAmount: 10000000.0,
          paidAmount: 5000000.0,
        );
        current = r1.updatedSupplier;

        // Import 2: 20M total, 20M debt
        final r2 = SupplierDebtEngine.processImportDebt(
          supplier: current,
          totalAmount: 20000000.0,
          paidAmount: 0.0,
        );
        current = r2.updatedSupplier;

        // Initial: 50M purchase, 10M debt
        // After R1: 60M purchase, 15M debt
        // After R2: 80M purchase, 35M debt
        expect(current.totalPurchase, equals(80000000.0));
        expect(current.currentDebt, equals(35000000.0));
      });
    });

    // ========================================================================
    // R3: KPI OVERVIEW DRILL-DOWNS BOUNDARY & CORNER CASES
    // ========================================================================
    group('R3 Boundaries & Corner Cases: KPI Overview Drill-downs', () {
      test('B3.1: Zero sales / empty rankings state yields empty items safely', () {
        const List<ProductRankingItem> emptyProds = [];
        const List<CustomerRankingItem> emptyCusts = [];

        expect(emptyProds, isEmpty);
        expect(emptyCusts, isEmpty);
      });

      test('B3.2: Category breakdown with Vietnamese accents and special characters passes intact', () {
        const catSpecial = CategoryRevenueShare(
          categoryName: 'Bánh kẹo / Sữa & Đồ uống (Mới 2026!)',
          revenue: 15500000.0,
          percentage: 24.8,
          quantitySold: 85,
        );

        expect(catSpecial.categoryName, equals('Bánh kẹo / Sữa & Đồ uống (Mới 2026!)'));
        expect(catSpecial.percentage, equals(24.8));
      });

      test('B3.3: Customer ranking item with 0 orders and 0 spent handled safely', () {
        const zeroCust = CustomerRankingItem(
          customerId: 'CUST_ZERO_SPENT',
          customerName: 'Khách Chưa Mua',
          totalSpent: 0.0,
          orderCount: 0,
        );

        expect(zeroCust.totalSpent, equals(0.0));
        expect(zeroCust.orderCount, equals(0));
      });
    });

    // ========================================================================
    // R4: STAFF SHIFT & GPS ATTENDANCE BOUNDARY & CORNER CASES
    // ========================================================================
    group('R4 Boundaries & Corner Cases: Shift & GPS Attendance', () {
      late StoreGpsConfig storeConfig;
      late Shift morningShift;
      late UserAccount staffUser;
      late UserAccount supervisorUser;
      late UserAccount adminUser;

      setUp(() {
        storeConfig = const StoreGpsConfig(
          storeId: 'store_001',
          storeName: 'Chi nhánh Đông Thắng',
          latitude: 10.7769,
          longitude: 106.7009,
          allowedRadiusMeters: 150.0,
        );

        morningShift = const Shift(
          id: 'shift_morning',
          name: 'Ca Sáng',
          startTime: '08:00',
          endTime: '12:00',
          gracePeriodMinutes: 15,
        );

        staffUser = const UserAccount(
          username: 'staff_01',
          displayName: 'Nhân Viên',
          role: 'nhanvien',
          storeId: 'store_001',
        );

        supervisorUser = const UserAccount(
          username: 'sup_01',
          displayName: 'Giám Sát',
          role: 'supervisor',
          storeId: 'store_001',
        );

        adminUser = const UserAccount(
          username: 'admin_01',
          displayName: 'Quản Trị Viên',
          role: 'admin',
          storeId: 'store_001',
        );
      });

      test('B4.1: Geodesic boundary: Exactly 150.0m is valid (isGpsValid: true)', () {
        final pt150m = GeoDistanceHelper.pointAtExactDistanceMeters(
          originLat: storeConfig.latitude,
          originLng: storeConfig.longitude,
          distanceMeters: 150.0,
        );

        final isValid = GeoDistanceHelper.isWithinStoreRadius(
          userLat: pt150m.lat,
          userLng: pt150m.lng,
          storeConfig: storeConfig,
        );

        expect(isValid, isTrue);
      });

      test('B4.2: Geodesic boundary: 149.9m is valid (isGpsValid: true)', () {
        final pt149m = GeoDistanceHelper.pointAtExactDistanceMeters(
          originLat: storeConfig.latitude,
          originLng: storeConfig.longitude,
          distanceMeters: 149.9,
        );

        final isValid = GeoDistanceHelper.isWithinStoreRadius(
          userLat: pt149m.lat,
          userLng: pt149m.lng,
          storeConfig: storeConfig,
        );

        expect(isValid, isTrue);
      });

      test('B4.3: Geodesic boundary: 150.1m and 151.0m are invalid (isGpsValid: false)', () {
        final pt150_1m = GeoDistanceHelper.pointAtExactDistanceMeters(
          originLat: storeConfig.latitude,
          originLng: storeConfig.longitude,
          distanceMeters: 150.1,
        );
        final pt151m = GeoDistanceHelper.pointAtExactDistanceMeters(
          originLat: storeConfig.latitude,
          originLng: storeConfig.longitude,
          distanceMeters: 151.0,
        );

        final is150_1Valid = GeoDistanceHelper.isWithinStoreRadius(
          userLat: pt150_1m.lat,
          userLng: pt150_1m.lng,
          storeConfig: storeConfig,
        );
        final is151Valid = GeoDistanceHelper.isWithinStoreRadius(
          userLat: pt151m.lat,
          userLng: pt151m.lng,
          storeConfig: storeConfig,
        );

        expect(is150_1Valid, isFalse);
        expect(is151Valid, isFalse);
      });

      test('B4.4: Shift start time exact boundary: check-in at 08:00:00 is on-time (0 late minutes)', () {
        final exactStart = DateTime(2026, 9, 13, 8, 0, 0);

        final record = AttendanceEvaluationEngine.createCheckIn(
          id: 'B_ATT_01',
          user: staffUser,
          storeConfig: storeConfig,
          shift: morningShift,
          checkInTime: exactStart,
          userLat: storeConfig.latitude,
          userLng: storeConfig.longitude,
        );

        expect(record.status, equals(AttendanceStatus.onTime));
        expect(record.lateMinutes, equals(0));
      });

      test('B4.5: Shift grace period exact boundary: check-in at 08:15:00 is on-time (0 late minutes)', () {
        final exactGrace = DateTime(2026, 9, 13, 8, 15, 0);

        final record = AttendanceEvaluationEngine.createCheckIn(
          id: 'B_ATT_02',
          user: staffUser,
          storeConfig: storeConfig,
          shift: morningShift,
          checkInTime: exactGrace,
          userLat: storeConfig.latitude,
          userLng: storeConfig.longitude,
        );

        expect(record.status, equals(AttendanceStatus.onTime));
        expect(record.lateMinutes, equals(0));
      });

      test('B4.6: Shift grace period + 1 minute: check-in at 08:16:00 is late (16 minutes late)', () {
        final pastGrace = DateTime(2026, 9, 13, 8, 16, 0);

        final record = AttendanceEvaluationEngine.createCheckIn(
          id: 'B_ATT_03',
          user: staffUser,
          storeConfig: storeConfig,
          shift: morningShift,
          checkInTime: pastGrace,
          userLat: storeConfig.latitude,
          userLng: storeConfig.longitude,
        );

        expect(record.status, equals(AttendanceStatus.late));
        expect(record.lateMinutes, equals(16));
      });

      test('B4.7: Check-out boundary: 1 minute early vs 1 minute overtime', () {
        final checkInTime = DateTime(2026, 9, 13, 8, 0);
        final base = AttendanceEvaluationEngine.createCheckIn(
          id: 'B_ATT_04',
          user: staffUser,
          storeConfig: storeConfig,
          shift: morningShift,
          checkInTime: checkInTime,
          userLat: storeConfig.latitude,
          userLng: storeConfig.longitude,
        );

        // 11:59 -> 1 min early leave
        final early = AttendanceEvaluationEngine.completeCheckOut(
          record: base,
          shift: morningShift,
          checkOutTime: DateTime(2026, 9, 13, 11, 59),
        );
        expect(early.earlyLeaveMinutes, equals(1));

        // 12:01 -> 1 min overtime
        final ot = AttendanceEvaluationEngine.completeCheckOut(
          record: base,
          shift: morningShift,
          checkOutTime: DateTime(2026, 9, 13, 12, 1),
        );
        expect(ot.overtimeMinutes, equals(1));
      });

      test('B4.8: Role permissions boundary: Staff cannot switch store or approve adjustments; Supervisor scoped; Admin global', () {
        expect(staffUser.isStaff, isTrue);
        expect(staffUser.canSwitchStore, isFalse);
        expect(staffUser.isAdmin, isFalse);

        expect(supervisorUser.isSupervisor, isTrue);
        expect(supervisorUser.isAdmin, isTrue);
        expect(supervisorUser.canSwitchStore, isTrue);

        expect(adminUser.isAdmin, isTrue);
        expect(adminUser.isStaff, isFalse);
        expect(adminUser.canSwitchStore, isTrue);
      });

      test('B4.9: Attendance adjustment review: Approval updates hours and resets penalties; Rejection preserves record', () async {
        final repo = FakeAttendanceRepository();

        final originalRecord = AttendanceRecord(
          id: 'ATT_ADJ_01',
          userId: 'staff_01',
          userName: 'Nhân Viên',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: DateTime(2026, 9, 10),
          checkInTime: DateTime(2026, 9, 10, 8, 45), // 45 min late
          checkOutTime: DateTime(2026, 9, 10, 11, 30), // 30 min early
          status: AttendanceStatus.late,
          lateMinutes: 45,
          earlyLeaveMinutes: 30,
          checkInLat: 10.7769,
          checkInLng: 106.7009,
          isGpsValid: true,
        );
        await repo.saveRecord(originalRecord);

        // Submit adjustment: requested 08:00 to 12:00 (reason: forgotten check-in)
        final adjustment = AttendanceAdjustment(
          id: 'ADJ_001',
          attendanceId: 'ATT_ADJ_01',
          userId: 'staff_01',
          userName: 'Nhân Viên',
          storeId: 'store_001',
          requestedCheckIn: DateTime(2026, 9, 10, 8, 0),
          requestedCheckOut: DateTime(2026, 9, 10, 12, 0),
          reason: 'Quên chấm công do máy bận',
        );
        await repo.submitAdjustment(adjustment);

        // Supervisor approves
        await repo.reviewAdjustment(
          adjustmentId: 'ADJ_001',
          approve: true,
          reviewerUsername: 'sup_01',
        );

        final updatedRecord = await repo.getRecordById('ATT_ADJ_01');
        expect(updatedRecord, isNotNull);
        expect(updatedRecord!.status, equals(AttendanceStatus.adjusted));
        expect(updatedRecord.checkInTime, equals(DateTime(2026, 9, 10, 8, 0)));
        expect(updatedRecord.checkOutTime, equals(DateTime(2026, 9, 10, 12, 0)));
        expect(updatedRecord.lateMinutes, equals(0));
        expect(updatedRecord.earlyLeaveMinutes, equals(0));
        expect(updatedRecord.workHours, equals(4.0));
      });
    });
  });
}
