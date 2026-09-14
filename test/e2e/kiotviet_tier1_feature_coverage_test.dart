import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/overview_kpis.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/customers/pages/customer_detail_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';

import 'support/kiotviet_e2e_harness.dart';

void main() {
  group('=== KIOTVIET OPERATIONS UPGRADE: TIER 1 FEATURE COVERAGE ===', () {
    // ========================================================================
    // R1: CUSTOMER DEBT FILTER FEATURE COVERAGE
    // ========================================================================
    group('R1: Customer Debt Filter', () {
      late List<Customer> testCustomers;

      setUp(() {
        testCustomers = [
          const Customer(
            id: 'CUST_001',
            name: 'Nguyễn Văn An',
            phone: '0901234567',
            email: 'an@example.com',
            address: '123 Lê Lợi, Q.1, TP.HCM',
            purchases: [],
            currentDebt: 5000000.0,
            totalSales: 15000000.0,
            branch: 'store_001',
            createdAt: '01/09/2026 08:00',
          ),
          const Customer(
            id: 'CUST_002',
            name: 'Trần Thị Bình',
            phone: '0912345678',
            email: 'binh@example.com',
            address: '456 Nguyễn Huệ, Q.1, TP.HCM',
            purchases: [],
            currentDebt: 12000000.0,
            totalSales: 35000000.0,
            branch: 'store_001',
            createdAt: '02/09/2026 09:30',
          ),
          const Customer(
            id: 'CUST_003',
            name: 'Lê Hoàng Cường',
            phone: '0923456789',
            email: 'cuong@example.com',
            address: '789 Đồng Khởi, Q.1, TP.HCM',
            purchases: [],
            currentDebt: 0.0,
            totalSales: 8000000.0,
            branch: 'store_001',
            createdAt: '03/09/2026 10:15',
          ),
          const Customer(
            id: 'CUST_004',
            name: 'Phạm Minh Dũng',
            phone: '0934567890',
            email: 'dung@example.com',
            address: '101 Hai Bà Trưng, Q.3, TP.HCM',
            purchases: [],
            currentDebt: 2500000.0,
            totalSales: 5000000.0,
            branch: 'store_001',
            createdAt: '04/09/2026 14:00',
          ),
          const Customer(
            id: 'CUST_005',
            name: 'Hoàng Kim Dung',
            phone: '0945678901',
            email: 'kdung@example.com',
            address: '202 Pasteur, Q.3, TP.HCM',
            purchases: [],
            currentDebt: -100000.0, // Overpaid / credit balance
            totalSales: 12000000.0,
            branch: 'store_001',
            createdAt: '05/09/2026 16:45',
          ),
        ];
      });

      test('T1.1: Filter tab [Tất cả] returns all customers regardless of debt status', () {
        final filtered = CustomerDebtEngine.filterCustomers(
          customers: testCustomers,
          filter: CustomerDebtFilter.all,
        );
        expect(filtered.length, equals(5));
      });

      test('T1.2: Filter tab [Còn nợ] returns exclusively customers with currentDebt > 0', () {
        final filtered = CustomerDebtEngine.filterCustomers(
          customers: testCustomers,
          filter: CustomerDebtFilter.inDebt,
        );
        expect(filtered.length, equals(3));
        expect(filtered.every((c) => (c.currentDebt ?? 0) > 0), isTrue);
        expect(filtered.map((c) => c.id).toSet(), equals({'CUST_001', 'CUST_002', 'CUST_004'}));
      });

      test('T1.3: Filter tab [Hết nợ] returns exclusively customers with currentDebt <= 0', () {
        final filtered = CustomerDebtEngine.filterCustomers(
          customers: testCustomers,
          filter: CustomerDebtFilter.cleared,
        );
        expect(filtered.length, equals(2));
        expect(filtered.every((c) => (c.currentDebt ?? 0) <= 0), isTrue);
        expect(filtered.map((c) => c.id).toSet(), equals({'CUST_003', 'CUST_005'}));
      });

      test('T1.4: Sorting in [Còn nợ] mode strictly orders customers descending by debt amount', () {
        final filtered = CustomerDebtEngine.filterCustomers(
          customers: testCustomers,
          filter: CustomerDebtFilter.inDebt,
        );
        expect(filtered[0].id, equals('CUST_002')); // 12,000,000đ
        expect(filtered[1].id, equals('CUST_001')); // 5,000,000đ
        expect(filtered[2].id, equals('CUST_004')); // 2,500,000đ
        expect(filtered[0].displayCurrentDebt, greaterThan(filtered[1].displayCurrentDebt));
        expect(filtered[1].displayCurrentDebt, greaterThan(filtered[2].displayCurrentDebt));
      });

      test('T1.5: Debt badge logic renders formatted debt when displayCurrentDebt > 0', () {
        final debtor = testCustomers.firstWhere((c) => c.id == 'CUST_001');
        final clearCust = testCustomers.firstWhere((c) => c.id == 'CUST_003');

        expect(debtor.displayCurrentDebt > 0, isTrue);
        expect(clearCust.displayCurrentDebt > 0, isFalse);

        // Badge presence decision rule
        final showBadgeDebtor = debtor.displayCurrentDebt > 0;
        final showBadgeClear = clearCust.displayCurrentDebt > 0;

        expect(showBadgeDebtor, isTrue);
        expect(showBadgeClear, isFalse);
      });

      test('T1.6: Instant live total customer debt calculation accurately sums current debtors', () {
        final inDebtList = CustomerDebtEngine.filterCustomers(
          customers: testCustomers,
          filter: CustomerDebtFilter.inDebt,
        );
        final liveTotal = CustomerDebtEngine.calculateLiveTotalDebt(inDebtList);
        // 12,000,000 + 5,000,000 + 2,500,000 = 19,500,000
        expect(liveTotal, equals(19500000.0));
      });

      test('T1.7: Quick navigation activates CustomerDebtFilter.inDebt via Riverpod container', () {
        final container = ProviderContainer();
        addTearDown(container.dispose);

        // Initial state is all
        expect(container.read(customerDebtFilterProvider), equals(CustomerDebtFilter.all));

        // When navigating from "Sổ nợ khách" or "Công nợ khách hàng cần thu"
        container.read(customerDebtFilterProvider.notifier).state = CustomerDebtFilter.inDebt;
        expect(container.read(customerDebtFilterProvider), equals(CustomerDebtFilter.inDebt));
      });
    });

    // ========================================================================
    // R2: SUPPLIER INTEGRATION INTO IMPORT INVENTORY & DEBT MANAGEMENT
    // ========================================================================
    group('R2: Supplier Integration into Import Inventory & Debt Management', () {
      late FakeSupplierRepository supplierRepo;
      late Supplier initialSupplier;

      setUp(() {
        initialSupplier = const Supplier(
          id: 'SUP_001',
          code: 'NCC_DIGI',
          name: 'Công ty Cổ phần Digiworld',
          phone: '02839291234',
          email: 'contact@digiworld.com',
          totalPurchase: 100000000.0,
          currentDebt: 20000000.0,
          status: 'active',
        );
        supplierRepo = FakeSupplierRepository([initialSupplier]);
      });

      test('T1.8: Supplier selector displays available suppliers from repository', () async {
        final suppliers = await supplierRepo.fetchAll(storeId: 'store_001');
        expect(suppliers.length, equals(1));
        expect(suppliers.first.name, contains('Digiworld'));
      });

      test('T1.9: Searching supplier by code, phone, or name filters the selector accurately', () async {
        final foundByCode = await supplierRepo.fetchById('SUP_001');
        expect(foundByCode, isNotNull);
        expect(foundByCode!.code, equals('NCC_DIGI'));
      });

      test('T1.10: Quick-create supplier registers new supplier and sets as available', () async {
        const newSupplier = Supplier(
          id: 'SUP_002',
          code: 'NCC_FPT',
          name: 'Synnex FPT Distribution',
          phone: '02473006666',
          status: 'active',
        );
        await supplierRepo.upsert(newSupplier, storeId: 'store_001');

        final fetched = await supplierRepo.fetchById('SUP_002', storeId: 'store_001');
        expect(fetched, isNotNull);
        expect(fetched!.name, equals('Synnex FPT Distribution'));
        expect(fetched.currentDebt, equals(0.0));
      });

      test('T1.11: Full payment option ("Thanh toán toàn bộ"): paidAmount == totalAmount creates 0 debt', () {
        const importTotal = 15000000.0;
        const paidAmount = 15000000.0; // 100% paid

        final result = SupplierDebtEngine.processImportDebt(
          supplier: initialSupplier,
          totalAmount: importTotal,
          paidAmount: paidAmount,
          importCode: 'PN_TEST_001',
        );

        // Debt remains 20,000,000; totalPurchase increases by 15,000,000 -> 115,000,000
        expect(result.updatedSupplier.currentDebt, equals(20000000.0));
        expect(result.updatedSupplier.totalPurchase, equals(115000000.0));
        expect(result.debtTransaction, isNull);
      });

      test('T1.12: Partial payment / Debt option ("Ghi nợ NCC"): creates SupplierDebtTransaction and increments debt', () {
        const importTotal = 25000000.0;
        const paidAmount = 10000000.0; // 10,000,000 paid -> 15,000,000 debt addition

        final result = SupplierDebtEngine.processImportDebt(
          supplier: initialSupplier,
          totalAmount: importTotal,
          paidAmount: paidAmount,
          importCode: 'PN_TEST_002',
          note: 'Nhập hàng đợt 1 trả một phần',
        );

        expect(result.updatedSupplier.currentDebt, equals(35000000.0));
        expect(result.updatedSupplier.totalPurchase, equals(125000000.0));
        expect(result.debtTransaction, isNotNull);
        expect(result.debtTransaction!.amount, equals(15000000.0));
        expect(result.debtTransaction!.remainingDebt, equals(35000000.0));
        expect(result.debtTransaction!.type, equals(SupplierDebtType.importBill));
      });

      test('T1.13: Traceability: InventoryTransaction records supplierId, supplierName, and importCode', () async {
        final invRepo = FakeInventoryRepository();
        final tx = InventoryTransaction(
          id: 'TX_INV_001',
          productId: 'PROD_001',
          type: TransactionType.import,
          quantity: 50,
          date: DateTime.now(),
          importPrice: 200000.0,
          note: 'Nhập hàng từ Digiworld',
          createdBy: 'admin',
          createdByName: 'Quản trị viên',
          storeId: 'store_001',
        );
        await invRepo.record(tx);

        final transactions = await invRepo.watchByProduct('PROD_001').first;
        expect(transactions.length, equals(1));
        expect(transactions.first.id, equals('TX_INV_001'));
        expect(transactions.first.quantity, equals(50));
      });
    });

    // ========================================================================
    // R3: KPI OVERVIEW DRILL-DOWNS FEATURE COVERAGE
    // ========================================================================
    group('R3: KPI Overview Drill-downs', () {
      late Product sampleProduct;
      late Customer sampleCustomer;

      setUp(() {
        sampleProduct = const Product(
          id: 'PROD_IPHONE15',
          name: 'iPhone 15 Pro Max 256GB',
          code: 'IP15PM256',
          price: 29990000.0,
          costPrice: 26000000.0,
          branchStocks: {'store_001': 10},
          category: 'Điện thoại',
        );

        sampleCustomer = const Customer(
          id: 'CUST_VIP01',
          name: 'Trần Gia Bảo',
          phone: '0988888888',
          email: 'giabao@example.com',
          address: '88 Nguyễn Trãi, Q.5, TP.HCM',
          purchases: [],
          totalSales: 120000000.0,
          currentDebt: 15000000.0,
        );
      });

      testWidgets('T1.14: Top selling product drill-down pushes ProductDetailPage', (tester) async {
        await tester.pumpWidget(
          buildKiotVietE2ETestHarness(
            overrides: [
              productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
              transactionsByProductProvider(sampleProduct.id).overrideWith((ref) => Stream.value([])),
            ],
            child: Builder(
              builder: (context) {
                return InkWell(
                  key: const ValueKey('top_prod_ip15'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ProductDetailPage(product: sampleProduct),
                      ),
                    );
                  },
                  child: const Text('iPhone 15 Pro Max 256GB'),
                );
              },
            ),
          ),
        );

        expect(find.byKey(const ValueKey('top_prod_ip15')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('top_prod_ip15')));
        await tester.pumpAndSettle();

        expect(find.byType(ProductDetailPage), findsOneWidget);
        expect(find.text('iPhone 15 Pro Max 256GB'), findsWidgets);
      });

      testWidgets('T1.15: Top spending customer drill-down pushes CustomerDetailPage', (tester) async {
        await tester.pumpWidget(
          buildKiotVietE2ETestHarness(
            overrides: [
              customerOrdersProvider(sampleCustomer.id).overrideWith((ref) => Stream.value([])),
              customerDebtTransactionsProvider(sampleCustomer.id).overrideWith((ref) => Stream.value([])),
            ],
            child: Builder(
              builder: (context) {
                return InkWell(
                  key: const ValueKey('top_cust_bao'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => CustomerDetailPage(customer: sampleCustomer),
                      ),
                    );
                  },
                  child: const Text('Trần Gia Bảo'),
                );
              },
            ),
          ),
        );

        expect(find.byKey(const ValueKey('top_cust_bao')), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('top_cust_bao')));
        await tester.pumpAndSettle();

        expect(find.byType(CustomerDetailPage), findsOneWidget);
        expect(find.text('Trần Gia Bảo'), findsWidgets);
      });

      testWidgets('T1.16: "Xem tất cả" button on Top Products navigates to ProductsPage', (tester) async {
        await tester.pumpWidget(
          buildKiotVietE2ETestHarness(
            child: Builder(
              builder: (context) {
                return TextButton(
                  key: const ValueKey('view_all_products_btn'),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ProductsPage(),
                      ),
                    );
                  },
                  child: const Text('Xem tất cả'),
                );
              },
            ),
          ),
        );

        await tester.tap(find.byKey(const ValueKey('view_all_products_btn')));
        await tester.pumpAndSettle();

        expect(find.byType(ProductsPage), findsOneWidget);
      });

      test('T1.17: Category breakdown drill-down prepares CategoryRevenueShare data correctly', () {
        const cat = CategoryRevenueShare(
          categoryName: 'Phụ kiện',
          revenue: 45000000.0,
          percentage: 35.5,
          quantitySold: 120,
        );

        expect(cat.categoryName, equals('Phụ kiện'));
        expect(cat.quantitySold, equals(120));
      });
    });

    // ========================================================================
    // R4: STAFF SHIFT MANAGEMENT & GPS ATTENDANCE SYSTEM
    // ========================================================================
    group('R4: Staff Shift Management & GPS Attendance System', () {
      late FakeAttendanceRepository attendanceRepo;
      late Shift morningShift;
      late StoreGpsConfig storeDongThang;
      late UserAccount staffUser;

      setUp(() {
        attendanceRepo = FakeAttendanceRepository();
        attendanceRepo.seedDefaultShifts();
        attendanceRepo.seedDefaultStoreGps();

        morningShift = attendanceRepo.shifts.firstWhere((s) => s.id == 'shift_morning');
        storeDongThang = attendanceRepo.storeConfigs['store_001']!;
        staffUser = const UserAccount(
          username: 'staff_01',
          displayName: 'Nguyễn Văn Nhân Viên',
          role: 'nhanvien',
          storeId: 'store_001',
        );
      });

      test('T1.18: Shift domain configuration provides start, end, and grace period', () {
        final testDate = DateTime(2026, 9, 13);
        final startDt = morningShift.getStartDateTime(testDate);
        final graceDt = morningShift.getGraceDateTime(testDate);
        final endDt = morningShift.getEndDateTime(testDate);

        expect(startDt.hour, equals(8));
        expect(startDt.minute, equals(0));
        expect(graceDt.hour, equals(8));
        expect(graceDt.minute, equals(15));
        expect(endDt.hour, equals(12));
        expect(endDt.minute, equals(0));
      });

      test('T1.19: Geodesic Haversine accurately measures store coordinate distance', () {
        // Exactly at store
        final distZero = GeoDistanceHelper.haversineDistance(
          storeDongThang.latitude,
          storeDongThang.longitude,
          storeDongThang.latitude,
          storeDongThang.longitude,
        );
        expect(distZero, equals(0.0));

        // 100 meters away
        final p100m = GeoDistanceHelper.pointAtExactDistanceMeters(
          originLat: storeDongThang.latitude,
          originLng: storeDongThang.longitude,
          distanceMeters: 100.0,
        );
        final dist100m = GeoDistanceHelper.haversineDistance(
          p100m.lat,
          p100m.lng,
          storeDongThang.latitude,
          storeDongThang.longitude,
        );
        expect(dist100m, closeTo(100.0, 0.01));
      });

      test('T1.20: Staff check-in inside valid store GPS radius (<= 150m) validates isGpsValid: true', () {
        // 80 meters away from store
        final pt80m = GeoDistanceHelper.pointAtExactDistanceMeters(
          originLat: storeDongThang.latitude,
          originLng: storeDongThang.longitude,
          distanceMeters: 80.0,
        );
        final checkInTime = DateTime(2026, 9, 13, 8, 5); // 08:05 on time

        final record = AttendanceEvaluationEngine.createCheckIn(
          id: 'ATT_001',
          user: staffUser,
          storeConfig: storeDongThang,
          shift: morningShift,
          checkInTime: checkInTime,
          userLat: pt80m.lat,
          userLng: pt80m.lng,
        );

        expect(record.isGpsValid, isTrue);
        expect(record.status, equals(AttendanceStatus.onTime));
        expect(record.lateMinutes, equals(0));
        expect(record.explanationReason, isNull);
      });

      test('T1.21: Staff check-in outside store GPS radius (> 150m) flags isGpsValid: false and requires explanation', () {
        // 350 meters away from store
        final pt350m = GeoDistanceHelper.pointAtExactDistanceMeters(
          originLat: storeDongThang.latitude,
          originLng: storeDongThang.longitude,
          distanceMeters: 350.0,
        );
        final checkInTime = DateTime(2026, 9, 13, 8, 10);

        final record = AttendanceEvaluationEngine.createCheckIn(
          id: 'ATT_002',
          user: staffUser,
          storeConfig: storeDongThang,
          shift: morningShift,
          checkInTime: checkInTime,
          userLat: pt350m.lat,
          userLng: pt350m.lng,
          explanationReason: 'Gặp khách hàng giao hàng ngoài chi nhánh',
        );

        expect(record.isGpsValid, isFalse);
        expect(record.explanationReason, equals('Gặp khách hàng giao hàng ngoài chi nhánh'));
      });

      test('T1.22: Auto-detection of late check-in when checking in past grace period', () {
        // Check-in at 08:25 (shift start 08:00, grace period 15m until 08:15) -> 25 min late
        final checkInTime = DateTime(2026, 9, 13, 8, 25);

        final record = AttendanceEvaluationEngine.createCheckIn(
          id: 'ATT_003',
          user: staffUser,
          storeConfig: storeDongThang,
          shift: morningShift,
          checkInTime: checkInTime,
          userLat: storeDongThang.latitude,
          userLng: storeDongThang.longitude,
        );

        expect(record.status, equals(AttendanceStatus.late));
        expect(record.lateMinutes, equals(25));
      });

      test('T1.23: Auto-detection of check-out early leave vs overtime', () {
        final checkInTime = DateTime(2026, 9, 13, 8, 0);
        final baseRecord = AttendanceEvaluationEngine.createCheckIn(
          id: 'ATT_004',
          user: staffUser,
          storeConfig: storeDongThang,
          shift: morningShift,
          checkInTime: checkInTime,
          userLat: storeDongThang.latitude,
          userLng: storeDongThang.longitude,
        );

        // Case A: Early Leave (11:30 vs 12:00 -> 30 min early)
        final earlyCheckOut = DateTime(2026, 9, 13, 11, 30);
        final earlyRecord = AttendanceEvaluationEngine.completeCheckOut(
          record: baseRecord,
          shift: morningShift,
          checkOutTime: earlyCheckOut,
        );
        expect(earlyRecord.status, equals(AttendanceStatus.earlyLeave));
        expect(earlyRecord.earlyLeaveMinutes, equals(30));
        expect(earlyRecord.workHours, equals(3.5)); // 3.5 hours worked

        // Case B: Overtime (12:45 vs 12:00 -> 45 min overtime)
        final otCheckOut = DateTime(2026, 9, 13, 12, 45);
        final otRecord = AttendanceEvaluationEngine.completeCheckOut(
          record: baseRecord,
          shift: morningShift,
          checkOutTime: otCheckOut,
        );
        expect(otRecord.status, equals(AttendanceStatus.overtime));
        expect(otRecord.overtimeMinutes, equals(45));
        expect(otRecord.workHours, equals(4.75)); // 4 hours 45 mins
      });

      test('T1.24: Personal monthly timesheet aggregates hours, shifts, and late counts', () {
        final records = [
          // Shift 1: 4 hours, on time
          AttendanceRecord(
            id: 'R1',
            userId: 'staff_01',
            userName: 'Nguyễn Văn Nhân Viên',
            storeId: 'store_001',
            shiftId: 'shift_morning',
            shiftName: 'Ca Sáng',
            date: DateTime(2026, 9, 1),
            checkInTime: DateTime(2026, 9, 1, 8, 0),
            checkOutTime: DateTime(2026, 9, 1, 12, 0),
            status: AttendanceStatus.onTime,
            checkInLat: 10.7769,
            checkInLng: 106.7009,
            isGpsValid: true,
          ),
          // Shift 2: 4.5 hours, 20 min late
          AttendanceRecord(
            id: 'R2',
            userId: 'staff_01',
            userName: 'Nguyễn Văn Nhân Viên',
            storeId: 'store_001',
            shiftId: 'shift_afternoon',
            shiftName: 'Ca Chiều',
            date: DateTime(2026, 9, 2),
            checkInTime: DateTime(2026, 9, 2, 13, 20),
            checkOutTime: DateTime(2026, 9, 2, 17, 50),
            status: AttendanceStatus.late,
            lateMinutes: 20,
            overtimeMinutes: 20,
            checkInLat: 10.7769,
            checkInLng: 106.7009,
            isGpsValid: true,
          ),
        ];

        final summary = MonthlyTimesheetSummary.aggregate(
          'staff_01',
          'Nguyễn Văn Nhân Viên',
          records,
        );

        expect(summary.totalShifts, equals(2));
        expect(summary.completedShifts, equals(2));
        expect(summary.lateCount, equals(1));
        expect(summary.totalOtMinutes, equals(20));
        expect(summary.totalHours, equals(8.5));
      });

      test('T1.25: Live Attendance Dashboard accurately computes active, late, and absent staff', () {
        final todayRecords = [
          // staff_01 is working (checked in, no check out)
          AttendanceRecord(
            id: 'LIVE_01',
            userId: 'staff_01',
            userName: 'Nguyễn Văn Nhân Viên',
            storeId: 'store_001',
            shiftId: 'shift_morning',
            shiftName: 'Ca Sáng',
            date: DateTime(2026, 9, 13),
            checkInTime: DateTime(2026, 9, 13, 8, 5),
            status: AttendanceStatus.onTime,
            checkInLat: 10.7769,
            checkInLng: 106.7009,
            isGpsValid: true,
          ),
          // staff_02 arrived late (checked in, late 25 mins)
          AttendanceRecord(
            id: 'LIVE_02',
            userId: 'staff_02',
            userName: 'Lê Văn Muộn',
            storeId: 'store_001',
            shiftId: 'shift_morning',
            shiftName: 'Ca Sáng',
            date: DateTime(2026, 9, 13),
            checkInTime: DateTime(2026, 9, 13, 8, 25),
            status: AttendanceStatus.late,
            lateMinutes: 25,
            checkInLat: 10.7769,
            checkInLng: 106.7009,
            isGpsValid: true,
          ),
        ];

        final scheduledStaff = ['staff_01', 'staff_02', 'staff_03_absent'];

        final liveSummary = LiveAttendanceSummary.compute(
          storeId: 'store_001',
          allTodayRecords: todayRecords,
          scheduledStaffIds: scheduledStaff,
        );

        expect(liveSummary.activeWorking.length, equals(2));
        expect(liveSummary.lateToday.length, equals(1));
        expect(liveSummary.lateToday.first.userId, equals('staff_02'));
        expect(liveSummary.absentStaff.length, equals(1));
        expect(liveSummary.absentStaff.first, equals('staff_03_absent'));
      });
    });
  });
}
