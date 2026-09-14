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
  group('=== KIOTVIET OPERATIONS UPGRADE: TIER 4 REAL-WORLD APPLICATION SCENARIOS ===', () {
    // ========================================================================
    // SCENARIO 1: MORNING STORE OPENING, GPS ATTENDANCE & SUPPLIER IMPORT DEBT
    // ========================================================================
    test('Scenario 1: Comprehensive Morning Store Opening, GPS Check-in, Goods Inward Delivery & Partial Payment', () async {
      // Step 1: Initialize Store Infrastructure & Repositories
      final attendanceRepo = FakeAttendanceRepository();
      attendanceRepo.seedDefaultShifts();
      attendanceRepo.seedDefaultStoreGps();

      final morningShift = attendanceRepo.shifts.firstWhere((s) => s.id == 'shift_morning');
      final storeGps = attendanceRepo.storeConfigs['store_001']!;

      const staff = UserAccount(
        username: 'staff_morning',
        displayName: 'Nguyễn Văn Thu Ngân',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      const supervisor = UserAccount(
        username: 'supervisor_dongthang',
        displayName: 'Trần Thị Quản Lý',
        role: 'supervisor',
        storeId: 'store_001',
      );

      // Step 2: Staff arrives at store (85m away), opens check-in at 08:05 (grace is 15m -> On Time)
      final staffPt = GeoDistanceHelper.pointAtExactDistanceMeters(
        originLat: storeGps.latitude,
        originLng: storeGps.longitude,
        distanceMeters: 85.0,
      );
      final checkInTime = DateTime(2026, 9, 13, 8, 5);

      final checkInRecord = AttendanceEvaluationEngine.createCheckIn(
        id: 'ATT_SC1_01',
        user: staff,
        storeConfig: storeGps,
        shift: morningShift,
        checkInTime: checkInTime,
        userLat: staffPt.lat,
        userLng: staffPt.lng,
      );
      await attendanceRepo.saveRecord(checkInRecord);

      expect(checkInRecord.isGpsValid, isTrue);
      expect(checkInRecord.status, equals(AttendanceStatus.onTime));
      expect(checkInRecord.lateMinutes, equals(0));

      // Step 3: Supervisor checks Live Attendance Dashboard -> sees staff actively working
      final liveDashboard = LiveAttendanceSummary.compute(
        storeId: 'store_001',
        allTodayRecords: [checkInRecord],
        scheduledStaffIds: ['staff_morning', 'staff_afternoon_scheduled'],
      );
      expect(liveDashboard.activeWorking.length, equals(1));
      expect(liveDashboard.activeWorking.first.userName, equals('Nguyễn Văn Thu Ngân'));
      expect(liveDashboard.lateToday, isEmpty);
      expect(liveDashboard.absentStaff, contains('staff_afternoon_scheduled'));

      // Step 4: Goods delivery truck arrives from Supplier "Ánh Dương Distribution"
      var supplier = const Supplier(
        id: 'SUP_ANHDUONG',
        code: 'NCC_AD',
        name: 'Công ty TNHH Phân Phối Ánh Dương',
        phone: '02838889999',
        totalPurchase: 80000000.0,
        currentDebt: 12000000.0,
      );

      var product = const Product(
        id: 'PROD_MILK',
        name: 'Sữa Tươi Tiệt Trùng Vinamilk 1L',
        code: 'VNM1L',
        price: 36000.0,
        costPrice: 28000.0,
        branchStocks: {'store_001': 15},
        category: 'Sữa & Bánh kẹo',
      );

      final invRepo = FakeInventoryRepository();
      final supplierRepo = FakeSupplierRepository([supplier]);
      final prodRepo = FakeProductRepository([product]);

      // Step 5: Supervisor imports 100 units at 28,000đ (Total 2,800,000đ).
      // Pays 1,000,000đ in cash, records remaining 1,800,000đ as debt.
      const importQty = 100;
      const totalCost = 2800000.0;
      const cashPaid = 1000000.0;
      const debtAddition = 1800000.0;

      final importDebtResult = SupplierDebtEngine.processImportDebt(
        supplier: supplier,
        totalAmount: totalCost,
        paidAmount: cashPaid,
        importCode: 'PN_20260913_001',
        note: 'Nhập sữa Vinamilk 1L đợt sáng',
        createdBy: supervisor.displayName ?? supervisor.username,
      );
      supplier = importDebtResult.updatedSupplier;
      await supplierRepo.upsert(supplier, storeId: 'store_001');

      if (importDebtResult.debtTransaction != null) {
        await supplierRepo.recordDebtTransaction(
          importDebtResult.debtTransaction!,
          storeId: 'store_001',
        );
      }

      // Step 6: Update product inventory & record transaction
      await prodRepo.updateStock(product.id, 15 + importQty);
      final tx = InventoryTransaction(
        id: 'TX_IMP_SC1_01',
        productId: product.id,
        type: TransactionType.import,
        quantity: importQty,
        date: DateTime.now(),
        importPrice: 28000.0,
        note: 'Nhập hàng từ NCC Ánh Dương',
        createdBy: supervisor.username,
        createdByName: supervisor.displayName,
        storeId: 'store_001',
      );
      await invRepo.record(tx);

      // Step 7: Verify end state of Morning Opening
      final updatedSup = await supplierRepo.fetchById('SUP_ANHDUONG', storeId: 'store_001');
      expect(updatedSup!.currentDebt, equals(12000000.0 + debtAddition)); // 13,800,000
      expect(updatedSup.totalPurchase, equals(80000000.0 + totalCost)); // 82,800,000

      final debtTxs = await supplierRepo.fetchDebtTransactions('SUP_ANHDUONG', storeId: 'store_001');
      expect(debtTxs.length, equals(1));
      expect(debtTxs.first.amount, equals(debtAddition));
      expect(debtTxs.first.type, equals(SupplierDebtType.importBill));

      final updatedProd = await prodRepo.fetchById(product.id);
      expect(updatedProd!.branchStocks['store_001'], equals(115));
    });

    // ========================================================================
    // SCENARIO 2: END-OF-DAY OPERATIONS, DEBT AUDIT & TIMESHEET CLOSING
    // ========================================================================
    test('Scenario 2: End-of-Day Operations, KPI Debt Audit, Overtime Check-out, and Timesheet Closing Workflow', () async {
      // Step 1: Customers Ledger State at End of Day
      final customers = [
        const Customer(
          id: 'CUST_VIP_1',
          name: 'Công ty Cổ phần Xây Dựng Nam Á',
          phone: '0901234888',
          email: 'nama@test.com',
          address: 'TP.HCM',
          purchases: [],
          currentDebt: 65000000.0,
          totalSales: 180000000.0,
          branch: 'store_001',
        ),
        const Customer(
          id: 'CUST_VIP_2',
          name: 'Cửa Hàng Tạp Hóa Minh Châu',
          phone: '0901234999',
          email: 'minhchau@test.com',
          address: 'TP.HCM',
          purchases: [],
          currentDebt: 32000000.0,
          totalSales: 95000000.0,
          branch: 'store_001',
        ),
        const Customer(
          id: 'CUST_REGULAR_1',
          name: 'Bà Nguyễn Thị Mai',
          phone: '0901234111',
          email: 'mai@test.com',
          address: 'TP.HCM',
          purchases: [],
          currentDebt: 0.0,
          totalSales: 22000000.0,
          branch: 'store_001',
        ),
      ];

      // Step 2: Store Manager audits KPI Overview -> "Công nợ khách hàng cần thu"
      final inDebtCustomers = CustomerDebtEngine.filterCustomers(
        customers: customers,
        filter: CustomerDebtFilter.inDebt,
      );

      expect(inDebtCustomers.length, equals(2));
      // Highest debtor first
      expect(inDebtCustomers.first.id, equals('CUST_VIP_1'));
      expect(inDebtCustomers.first.displayCurrentDebt, equals(65000000.0));
      expect(inDebtCustomers.last.id, equals('CUST_VIP_2'));
      expect(inDebtCustomers.last.displayCurrentDebt, equals(32000000.0));

      // Live total debt matches KPI card
      final totalDebt = CustomerDebtEngine.calculateLiveTotalDebt(inDebtCustomers);
      expect(totalDebt, equals(97000000.0));

      // Step 3: Staff completes shift with 35 min overtime (Shift end 12:00 -> Check-out 12:35)
      final attendanceRepo = FakeAttendanceRepository();
      attendanceRepo.seedDefaultShifts();
      attendanceRepo.seedDefaultStoreGps();

      final morningShift = attendanceRepo.shifts.firstWhere((s) => s.id == 'shift_morning');
      final storeGps = attendanceRepo.storeConfigs['store_001']!;

      const staff = UserAccount(
        username: 'staff_eod',
        displayName: 'Trần Văn Ca Sáng',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      final checkIn = AttendanceEvaluationEngine.createCheckIn(
        id: 'ATT_EOD_01',
        user: staff,
        storeConfig: storeGps,
        shift: morningShift,
        checkInTime: DateTime(2026, 9, 13, 7, 58), // 2 min early -> on time
        userLat: storeGps.latitude,
        userLng: storeGps.longitude,
      );

      final checkOut = AttendanceEvaluationEngine.completeCheckOut(
        record: checkIn,
        shift: morningShift,
        checkOutTime: DateTime(2026, 9, 13, 12, 35), // 35 min overtime
      );
      await attendanceRepo.saveRecord(checkOut);

      expect(checkOut.status, equals(AttendanceStatus.overtime));
      expect(checkOut.overtimeMinutes, equals(35));
      expect(checkOut.workHours, greaterThanOrEqualTo(4.5));

      // Step 4: Supervisor closes day by reviewing Monthly Timesheet
      final timesheet = MonthlyTimesheetSummary.aggregate(
        'staff_eod',
        'Trần Văn Ca Sáng',
        [checkOut],
      );

      expect(timesheet.totalShifts, equals(1));
      expect(timesheet.completedShifts, equals(1));
      expect(timesheet.lateCount, equals(0));
      expect(timesheet.totalOtMinutes, equals(35));
    });
  });
}
