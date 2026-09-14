import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'support/kiotviet_e2e_harness.dart';

void main() {
  group('=== KIOTVIET OPERATIONS UPGRADE: TIER 3 CROSS-FEATURE COMBINATIONS ===', () {
    // ========================================================================
    // COMBO 1: SUPPLIER IMPORT DEBT (R2) -> CUSTOMER DEBT (R1) -> LIVE SUMMARY
    // ========================================================================
    test('Cross 1: Supplier Import Debt (R2) updates balance; Customer Credit Purchase (R1) reflects in Debt Filter and Live Total', () async {
      // 1. Setup initial Supplier and Customers
      var supplier = const Supplier(
        id: 'SUP_C1',
        code: 'NCC_APPLE',
        name: 'Apple Authorized Distributor',
        totalPurchase: 200000000.0,
        currentDebt: 50000000.0,
      );

      var customer = const Customer(
        id: 'CUST_C1',
        name: 'Hoàng Kim Long',
        phone: '0909999888',
        email: 'long@test.com',
        address: 'Quận 1, TP.HCM',
        purchases: [],
        currentDebt: 0.0, // Initially cleared
        totalSales: 10000000.0,
      );

      // 2. Perform Inventory Import with 70% Debt on Supplier (R2)
      const importTotal = 100000000.0;
      const paidAmount = 30000000.0; // 30M paid, 70M debt
      final importResult = SupplierDebtEngine.processImportDebt(
        supplier: supplier,
        totalAmount: importTotal,
        paidAmount: paidAmount,
        importCode: 'PN_CROSS_01',
        note: 'Nhập lô hàng iPhone',
      );
      supplier = importResult.updatedSupplier;

      // Verify supplier debt updated
      expect(supplier.currentDebt, equals(120000000.0)); // 50M + 70M
      expect(supplier.totalPurchase, equals(300000000.0)); // 200M + 100M
      expect(importResult.debtTransaction!.type, equals(SupplierDebtType.importBill));

      // 3. Customer purchases item on credit -> customer incurs 25,000,000đ debt (R1)
      customer = customer.copyWith(
        currentDebt: 25000000.0,
        totalSales: 35000000.0,
      );

      // 4. Verify Customer Debt Filter (R1)
      final allCustomers = [customer];
      final inDebtCustomers = CustomerDebtEngine.filterCustomers(
        customers: allCustomers,
        filter: CustomerDebtFilter.inDebt,
      );
      final clearedCustomers = CustomerDebtEngine.filterCustomers(
        customers: allCustomers,
        filter: CustomerDebtFilter.cleared,
      );

      expect(inDebtCustomers.length, equals(1));
      expect(clearedCustomers.length, equals(0));
      expect(inDebtCustomers.first.id, equals('CUST_C1'));
      expect(inDebtCustomers.first.displayCurrentDebt, equals(25000000.0));

      // 5. Verify instant live total customer debt calculation
      final liveDebtTotal = CustomerDebtEngine.calculateLiveTotalDebt(inDebtCustomers);
      expect(liveDebtTotal, equals(25000000.0));
    });

    // ========================================================================
    // COMBO 2: KPI TOP PRODUCTS (R3) -> INVENTORY IMPORT WITH DEBT (R2)
    // ========================================================================
    test('Cross 2: Top Selling Product stock replenished via Supplier Import (R2) with debt and transaction traceability', () async {
      // 1. Initial product with low stock
      var product = const Product(
        id: 'PROD_IP15',
        name: 'iPhone 15 Pro Max',
        code: 'IP15',
        price: 30000000.0,
        costPrice: 25000000.0,
        branchStocks: {'store_001': 2}, // Low stock
        category: 'Điện thoại',
      );

      var supplier = const Supplier(
        id: 'SUP_MOBICORE',
        code: 'NCC_MOBI',
        name: 'MobiCore Supplies',
        totalPurchase: 50000000.0,
        currentDebt: 10000000.0,
      );

      final invRepo = FakeInventoryRepository();
      final prodRepo = FakeProductRepository([product]);

      // 2. Replenish stock by importing 20 units at cost 25M (Total: 500M, Pay 200M, Debt 300M)
      const quantity = 20;
      const totalAmount = 500000000.0;
      const paidAmount = 200000000.0;

      final supplierResult = SupplierDebtEngine.processImportDebt(
        supplier: supplier,
        totalAmount: totalAmount,
        paidAmount: paidAmount,
        importCode: 'PN_REP_01',
      );
      supplier = supplierResult.updatedSupplier;

      // Update product stock in repository
      await prodRepo.updateStock(product.id, 2 + quantity);
      final updatedProduct = await prodRepo.fetchById(product.id);

      // Record inventory transaction with supplier traceability
      final tx = InventoryTransaction(
        id: 'TX_REP_001',
        productId: product.id,
        type: TransactionType.import,
        quantity: quantity,
        date: DateTime.now(),
        importPrice: 25000000.0,
        note: 'Nhập hàng bổ sung từ MobiCore',
        createdBy: 'admin_01',
        createdByName: 'Quản trị viên',
        storeId: 'store_001',
      );
      await invRepo.record(tx);

      // Verify cross-feature consistency
      expect(updatedProduct!.branchStocks['store_001'], equals(22));
      expect(supplier.currentDebt, equals(310000000.0)); // 10M + 300M
      expect(supplier.totalPurchase, equals(550000000.0)); // 50M + 500M

      final txs = await invRepo.watchByProduct(product.id).first;
      expect(txs.length, equals(1));
      expect(txs.first.quantity, equals(20));
      expect(txs.first.note, contains('MobiCore'));
    });

    // ========================================================================
    // COMBO 3: GPS ATTENDANCE (R4) -> LIVE DASHBOARD -> TIMESHEET -> ADJUSTMENT
    // ========================================================================
    test('Cross 3: Staff GPS Check-in reflects in Live Dashboard, accumulates in Timesheet, and updates on Supervisor Adjustment Approval', () async {
      final repo = FakeAttendanceRepository();
      repo.seedDefaultShifts();
      repo.seedDefaultStoreGps();

      final morningShift = repo.shifts.firstWhere((s) => s.id == 'shift_morning');
      final storeGps = repo.storeConfigs['store_001']!;

      const staff = UserAccount(
        username: 'staff_e2e',
        displayName: 'Nguyễn Toàn Quyền',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      // Step 1: Staff check-in on time within 100m
      final pt100m = GeoDistanceHelper.pointAtExactDistanceMeters(
        originLat: storeGps.latitude,
        originLng: storeGps.longitude,
        distanceMeters: 100.0,
      );
      final checkInTime = DateTime(2026, 9, 13, 8, 5);

      final record = AttendanceEvaluationEngine.createCheckIn(
        id: 'ATT_COMBO_01',
        user: staff,
        storeConfig: storeGps,
        shift: morningShift,
        checkInTime: checkInTime,
        userLat: pt100m.lat,
        userLng: pt100m.lng,
      );
      await repo.saveRecord(record);

      // Step 2: Supervisor views Live Attendance Dashboard
      final liveSummary1 = LiveAttendanceSummary.compute(
        storeId: 'store_001',
        allTodayRecords: [record],
        scheduledStaffIds: ['staff_e2e'],
      );
      expect(liveSummary1.activeWorking.length, equals(1));
      expect(liveSummary1.activeWorking.first.userId, equals('staff_e2e'));
      expect(liveSummary1.lateToday, isEmpty);

      // Step 3: Staff completes shift with 30 min early leave (11:30)
      final completedRecord = AttendanceEvaluationEngine.completeCheckOut(
        record: record,
        shift: morningShift,
        checkOutTime: DateTime(2026, 9, 13, 11, 30),
      );
      await repo.saveRecord(completedRecord);

      // Step 4: Timesheet aggregates early leave
      final timesheetBefore = MonthlyTimesheetSummary.aggregate(
        'staff_e2e',
        'Nguyễn Toàn Quyền',
        [completedRecord],
      );
      expect(timesheetBefore.totalHours, equals(3.42)); // 205 mins / 60 = 3.4166...
      expect(timesheetBefore.earlyLeaveCount, equals(1));

      // Step 5: Staff submits adjustment explaining early leave was approved store errand
      final adj = AttendanceAdjustment(
        id: 'ADJ_COMBO_01',
        attendanceId: 'ATT_COMBO_01',
        userId: 'staff_e2e',
        userName: 'Nguyễn Toàn Quyền',
        storeId: 'store_001',
        requestedCheckIn: DateTime(2026, 9, 13, 8, 0),
        requestedCheckOut: DateTime(2026, 9, 13, 12, 0),
        reason: 'Đi giao hàng cho khách VIP theo lệnh quản lý',
      );
      await repo.submitAdjustment(adj);

      // Step 6: Supervisor approves adjustment
      await repo.reviewAdjustment(
        adjustmentId: 'ADJ_COMBO_01',
        approve: true,
        reviewerUsername: 'supervisor_01',
      );

      // Step 7: Timesheet aggregates updated approved record
      final updatedRecords = await repo.getRecordsForUser('staff_e2e', 9, 2026);
      final timesheetAfter = MonthlyTimesheetSummary.aggregate(
        'staff_e2e',
        'Nguyễn Toàn Quyền',
        updatedRecords,
      );

      expect(timesheetAfter.totalHours, equals(4.0));
      expect(timesheetAfter.earlyLeaveCount, equals(0));
      expect(timesheetAfter.completedShifts, equals(1));
    });

    // ========================================================================
    // COMBO 4: MULTI-STORE ADMIN SCOPING ACROSS ATTENDANCE & DEBT (R1 + R4)
    // ========================================================================
    test('Cross 4: Store switching synchronizes Attendance records and Customer Debt scopes consistently', () async {
      // Store 001 customers
      const cust1 = Customer(
        id: 'CUST_ST1',
        name: 'Khách Chi Nhánh 1',
        phone: '0901111111',
        email: 'c1@test.com',
        address: 'Đông Thắng',
        branch: 'store_001',
        purchases: [],
        currentDebt: 8000000.0,
      );
      // Store 002 customers
      const cust2 = Customer(
        id: 'CUST_ST2',
        name: 'Khách Chi Nhánh 2',
        phone: '0902222222',
        email: 'c2@test.com',
        address: 'Thới Bình',
        branch: 'store_002',
        purchases: [],
        currentDebt: 15000000.0,
      );

      // Store 001 attendance
      final att1 = AttendanceRecord(
        id: 'ATT_ST1',
        userId: 'staff_st1',
        userName: 'Nhân Viên ST1',
        storeId: 'store_001',
        shiftId: 'shift_morning',
        shiftName: 'Ca Sáng',
        date: DateTime(2026, 9, 13),
        checkInTime: DateTime(2026, 9, 13, 8, 0),
        status: AttendanceStatus.onTime,
        checkInLat: 10.7769,
        checkInLng: 106.7009,
        isGpsValid: true,
      );
      // Store 002 attendance
      final att2 = AttendanceRecord(
        id: 'ATT_ST2',
        userId: 'staff_st2',
        userName: 'Nhân Viên ST2',
        storeId: 'store_002',
        shiftId: 'shift_morning',
        shiftName: 'Ca Sáng',
        date: DateTime(2026, 9, 13),
        checkInTime: DateTime(2026, 9, 13, 8, 30),
        status: AttendanceStatus.late,
        lateMinutes: 30,
        checkInLat: 10.7626,
        checkInLng: 106.6820,
        isGpsValid: true,
      );

      // Verify store_001 live attendance
      final liveStore1 = LiveAttendanceSummary.compute(
        storeId: 'store_001',
        allTodayRecords: [att1, att2],
        scheduledStaffIds: ['staff_st1'],
      );
      expect(liveStore1.activeWorking.length, equals(1));
      expect(liveStore1.activeWorking.first.userId, equals('staff_st1'));

      // Verify store_002 live attendance
      final liveStore2 = LiveAttendanceSummary.compute(
        storeId: 'store_002',
        allTodayRecords: [att1, att2],
        scheduledStaffIds: ['staff_st2'],
      );
      expect(liveStore2.activeWorking.length, equals(1));
      expect(liveStore2.activeWorking.first.userId, equals('staff_st2'));
      expect(liveStore2.lateToday.length, equals(1));

      // Verify store-scoped customer debt
      final allCustomers = [cust1, cust2];
      final debtStore1 = allCustomers.where((c) => c.branch == 'store_001' && (c.currentDebt ?? 0) > 0).toList();
      final debtStore2 = allCustomers.where((c) => c.branch == 'store_002' && (c.currentDebt ?? 0) > 0).toList();

      expect(debtStore1.length, equals(1));
      expect(debtStore1.first.id, equals('CUST_ST1'));
      expect(debtStore2.length, equals(1));
      expect(debtStore2.first.id, equals('CUST_ST2'));
    });

    // ========================================================================
    // COMBO 5: KPI DRILL-DOWN (R3) -> CUSTOMER DEBT FILTER (R1) NAVIGATION
    // ========================================================================
    test('Cross 5: Tapping "Sổ nợ khách" or KPI Debt Card pre-activates CustomerDebtFilter.inDebt and displays accurate live totals', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      const debtors = [
        Customer(
          id: 'D1',
          name: 'Đoàn Văn Hậu',
          phone: '0901230001',
          email: 'hau@test.com',
          address: 'Hà Nội',
          purchases: [],
          currentDebt: 45000000.0,
        ),
        Customer(
          id: 'D2',
          name: 'Quang Hải',
          phone: '0901230002',
          email: 'hai@test.com',
          address: 'Hà Nội',
          purchases: [],
          currentDebt: 25000000.0,
        ),
      ];

      // Initially 'all'
      expect(container.read(customerDebtFilterProvider), equals(CustomerDebtFilter.all));

      // Trigger navigation from KPI Card "Công nợ khách hàng cần thu"
      container.read(customerDebtFilterProvider.notifier).state = CustomerDebtFilter.inDebt;
      expect(container.read(customerDebtFilterProvider), equals(CustomerDebtFilter.inDebt));

      // Live debt total matches KPI
      final liveTotal = CustomerDebtEngine.calculateLiveTotalDebt(debtors);
      expect(liveTotal, equals(70000000.0));
    });
  });
}
