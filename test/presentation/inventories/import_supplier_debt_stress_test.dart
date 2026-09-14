import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _TestSupplierListNotifier
    extends AutoDisposeAsyncNotifier<List<Supplier>>
    implements SupplierListNotifier {
  final List<Supplier> initialData;
  final List<Map<String, dynamic>> recordedImportDebts;

  _TestSupplierListNotifier(this.initialData,
      [List<Map<String, dynamic>>? recordedList])
      : recordedImportDebts = recordedList ?? [];

  @override
  Future<List<Supplier>> build() async => initialData;

  @override
  Future<void> refresh() async {
    state = AsyncData(initialData);
  }

  @override
  Future<void> upsertSupplier(Supplier supplier) async {}

  @override
  Future<void> deleteSupplier(String id) async {}

  @override
  Future<void> recordDebtPayment({
    required String supplierId,
    required double paymentAmount,
    String? referenceCode,
    String? note,
    String createdBy = 'Admin',
  }) async {}

  @override
  Future<void> recordDebtAdjustment({
    required String supplierId,
    required double newDebt,
    String? note,
    String createdBy = 'Admin',
  }) async {}

  @override
  Future<void> recordImportDebt({
    required String supplierId,
    required double totalAmount,
    required double paidAmount,
    String? importCode,
    String? note,
    String createdBy = 'Admin',
  }) async {
    recordedImportDebts.add({
      'supplierId': supplierId,
      'totalAmount': totalAmount,
      'paidAmount': paidAmount,
      'importCode': importCode,
      'note': note,
      'createdBy': createdBy,
    });
  }
}

class _FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> recordedTransactions = [];

  @override
  Future<void> record(InventoryTransaction transaction) async {
    recordedTransactions.add(transaction);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value([]);

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime startDate, DateTime endDate) =>
      Stream.value([]);
}

class _FakeProductRepository implements ProductRepository {
  final List<Product> upsertedProducts = [];

  @override
  Future<void> upsert(Product product) async {
    upsertedProducts.add(product);
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Product?> fetchById(String id) async => null;

  @override
  Future<List<Product>> fetchAll() async => [];

  @override
  Future<void> updateStock(String id, int newStock) async {}

  @override
  Stream<List<Product>> watchAll() => Stream.value([]);
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const supervisorUser = UserAccount(
    username: 'supervisor_stress',
    displayName: 'Giám sát viên Thử Thách',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_stress',
    displayName: 'Nhân viên Thử Thách',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const productA = Product(
    id: 'prod_stress_01',
    name: 'Sản phẩm Cấu hình Cao',
    code: 'SP_PRO_MAX',
    price: 500000,
    costPrice: 300000,
    branchStocks: {'store_001': 5},
    category: 'Thiết bị điện tử',
  );


  const supplierHaNoi = Supplier(
    id: 'NCC_HN',
    code: 'NCC_HN',
    name: 'Nhà Phân Phối Hà Nội',
    phone: '0987654321',
    email: 'hanoi@distributor.vn',
    address: 'Ba Đình, Hà Nội',
    taxCode: '0101010101',
    totalPurchase: 10000000,
    currentDebt: 5000000,
    status: 'active',
  );

  const supplierDaNang = Supplier(
    id: 'NCC_DN',
    code: 'NCC_DN',
    name: 'Đại Lý Đà Nẵng',
    phone: '0912345678',
    email: 'danang@agency.vn',
    address: 'Hải Châu, Đà Nẵng',
    taxCode: '0404040404',
    totalPurchase: 5000000,
    currentDebt: 0,
    status: 'active',
  );

  const supplierDongThap = Supplier(
    id: 'NCC_DT',
    code: 'NCC_DT',
    name: 'Đồng Tháp Mười',
    phone: '02773888999',
    email: 'dongthap@supply.vn',
    address: 'Cao Lãnh, Đồng Tháp',
    taxCode: '1414141414',
    totalPurchase: 2000000,
    currentDebt: 1000000,
    status: 'active',
  );

  final testSuppliers = [supplierHaNoi, supplierDaNang, supplierDongThap];

  group('Milestone 2 Stress: Debt Calculation Boundaries', () {
    testWidgets('Boundary 1: 0 Paid (100% Debt) results in full debt recorded',
        (tester) async {
      final recordedDebts = <Map<String, dynamic>>[];
      final fakeInvRepo = _FakeInventoryRepository();
      final fakeProdRepo = _FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([productA])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(testSuppliers, recordedDebts),
            ),
            inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
            productRepositoryProvider.overrideWithValue(fakeProdRepo),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select productA
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Cấu hình Cao');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Cấu hình Cao').last);
      await tester.pumpAndSettle();

      // Select supplier
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhà Phân Phối Hà Nội'));
      await tester.pumpAndSettle();

      // Switch to Ghi nợ NCC
      await tester.ensureVisible(find.text('Ghi nợ NCC'));
      await tester.tap(find.text('Ghi nợ NCC'));
      await tester.pumpAndSettle();

      // Set paid amount to '0'
      await tester.ensureVisible(find.byKey(const Key('paid_amount_field')));
      await tester.enterText(find.byKey(const Key('paid_amount_field')), '0');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(recordedDebts.length, 1);
      expect(recordedDebts.first['supplierId'], 'NCC_HN');
      expect(recordedDebts.first['totalAmount'], 300000.0);
      expect(recordedDebts.first['paidAmount'], 0.0);
    });

    testWidgets('Boundary 2: Full Paid (0 Debt) results in paidAmount == totalAmount',
        (tester) async {
      final recordedDebts = <Map<String, dynamic>>[];
      final fakeInvRepo = _FakeInventoryRepository();
      final fakeProdRepo = _FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([productA])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(testSuppliers, recordedDebts),
            ),
            inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
            productRepositoryProvider.overrideWithValue(fakeProdRepo),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select productA
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Cấu hình Cao');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Cấu hình Cao').last);
      await tester.pumpAndSettle();

      // Select supplier
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhà Phân Phối Hà Nội'));
      await tester.pumpAndSettle();

      // Keep default 'Thanh toán toàn bộ'
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(recordedDebts.length, 1);
      expect(recordedDebts.first['totalAmount'], 300000.0);
      expect(recordedDebts.first['paidAmount'], 300000.0);
    });

    testWidgets('Boundary 3: Partial payment calculates exact debt difference',
        (tester) async {
      final recordedDebts = <Map<String, dynamic>>[];
      final fakeInvRepo = _FakeInventoryRepository();
      final fakeProdRepo = _FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([productA])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(testSuppliers, recordedDebts),
            ),
            inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
            productRepositoryProvider.overrideWithValue(fakeProdRepo),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select productA
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Cấu hình Cao');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Cấu hình Cao').last);
      await tester.pumpAndSettle();

      // Select supplier
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhà Phân Phối Hà Nội'));
      await tester.pumpAndSettle();

      // Ghi nợ NCC
      await tester.ensureVisible(find.text('Ghi nợ NCC'));
      await tester.tap(find.text('Ghi nợ NCC'));
      await tester.pumpAndSettle();

      // Partial payment of 120,000 đ
      await tester.ensureVisible(find.byKey(const Key('paid_amount_field')));
      await tester.enterText(find.byKey(const Key('paid_amount_field')), '120000');
      await tester.pumpAndSettle();

      // Preview displays debt increase 180,000 đ
      expect(find.textContaining('180.000'), findsWidgets);

      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(recordedDebts.length, 1);
      expect(recordedDebts.first['totalAmount'], 300000.0);
      expect(recordedDebts.first['paidAmount'], 120000.0);
    });

    testWidgets('Boundary 4: Overpayment is clamped to totalAmount without generating negative debt',
        (tester) async {
      final recordedDebts = <Map<String, dynamic>>[];
      final fakeInvRepo = _FakeInventoryRepository();
      final fakeProdRepo = _FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([productA])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(testSuppliers, recordedDebts),
            ),
            inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
            productRepositoryProvider.overrideWithValue(fakeProdRepo),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select productA
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Cấu hình Cao');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Cấu hình Cao').last);
      await tester.pumpAndSettle();

      // Select supplier
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhà Phân Phối Hà Nội'));
      await tester.pumpAndSettle();

      // Switch to Ghi nợ NCC
      await tester.ensureVisible(find.text('Ghi nợ NCC'));
      await tester.tap(find.text('Ghi nợ NCC'));
      await tester.pumpAndSettle();

      // Enter overpayment 999,999,999 đ (far exceeding 300,000 đ)
      await tester.ensureVisible(find.byKey(const Key('paid_amount_field')));
      await tester.enterText(
          find.byKey(const Key('paid_amount_field')), '999999999');
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(recordedDebts.length, 1);
      // Clamped to 300000.0
      expect(recordedDebts.first['paidAmount'], 300000.0);
      expect(recordedDebts.first['totalAmount'], 300000.0);
    });

    testWidgets('Boundary 5: Formatted inputs (periods/commas) parse cleanly',
        (tester) async {
      final recordedDebts = <Map<String, dynamic>>[];
      final fakeInvRepo = _FakeInventoryRepository();
      final fakeProdRepo = _FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([productA])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(testSuppliers, recordedDebts),
            ),
            inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
            productRepositoryProvider.overrideWithValue(fakeProdRepo),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select productA
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Cấu hình Cao');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Cấu hình Cao').last);
      await tester.pumpAndSettle();

      // Select supplier
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhà Phân Phối Hà Nội'));
      await tester.pumpAndSettle();

      // Ghi nợ NCC
      await tester.ensureVisible(find.text('Ghi nợ NCC'));
      await tester.tap(find.text('Ghi nợ NCC'));
      await tester.pumpAndSettle();

      // Input with thousands separators: "150.000"
      await tester.ensureVisible(find.byKey(const Key('paid_amount_field')));
      await tester.enterText(
          find.byKey(const Key('paid_amount_field')), '150.000');
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      expect(recordedDebts.length, 1);
      expect(recordedDebts.first['paidAmount'], 150000.0);
    });
  });

  group('Milestone 2 Stress: Validation Guards', () {
    testWidgets(
        'Validation: Attempting to save with Ghi nợ NCC without supplier is strictly blocked',
        (tester) async {
      final fakeInvRepo = _FakeInventoryRepository();
      final recordedDebts = <Map<String, dynamic>>[];

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([productA])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(testSuppliers, recordedDebts),
            ),
            inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select product
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Cấu hình Cao');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Cấu hình Cao').last);
      await tester.pumpAndSettle();

      // Select Ghi nợ NCC without selecting a supplier
      await tester.ensureVisible(find.text('Ghi nợ NCC'));
      await tester.tap(find.text('Ghi nợ NCC'));
      await tester.pumpAndSettle();

      // Warning message should be visible on screen
      expect(find.text('Chưa chọn Nhà Cung Cấp. Vui lòng chọn NCC để ghi nợ.'),
          findsOneWidget);

      // Attempt to save
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Blocked with SnackBar
      expect(find.text('Vui lòng chọn Nhà Cung Cấp để ghi nợ'), findsOneWidget);
      // Zero transactions recorded
      expect(fakeInvRepo.recordedTransactions, isEmpty);
      expect(recordedDebts, isEmpty);
    });
  });

  group('Milestone 2 Stress: Staff Role Masking', () {
    testWidgets(
        'Staff user cannot view unit prices, total values, or debt preview breakdown',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productListProvider.overrideWith((ref) => Stream.value([productA])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(testSuppliers),
            ),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // 1. Check unit price field is masked
      expect(find.text('Giá nhập'), findsNothing);
      expect(find.text('Tổng giá trị'), findsNothing);

      // 2. Select product
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Cấu hình Cao');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Cấu hình Cao').last);
      await tester.pumpAndSettle();

      // Price still not visible
      expect(find.text('Giá nhập'), findsNothing);
      expect(find.text('300.000 đ'), findsNothing);

      // 3. Payment options
      expect(find.text('Ghi nợ NCC (100%)'), findsOneWidget);
      expect(
        find.text('Đơn vị tính giá vốn tự động theo định mức hệ thống'),
        findsOneWidget,
      );

      // Select 'Ghi nợ NCC (100%)'
      await tester.ensureVisible(find.text('Ghi nợ NCC (100%)'));
      await tester.tap(find.text('Ghi nợ NCC (100%)'));
      await tester.pumpAndSettle();

      // Paid amount field and breakdown are hidden
      expect(find.byKey(const Key('paid_amount_field')), findsNothing);
      expect(find.text('Chi tiết công nợ phát sinh:'), findsNothing);
      expect(find.text('Ghi nhận nợ NCC:'), findsNothing);
    });
  });

  group('Milestone 2 Stress: Diacritic-Free Search in Supplier Selector', () {
    testWidgets('Search matches with unaccented, mixed case, and partial phone/code',
        (tester) async {
      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([productA])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(testSuppliers),
            ),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Open bottom sheet
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();

      final searchBox = find.byKey(const Key('supplier_search_field'));

      // Test 1: "ha noi" matches "Nhà Phân Phối Hà Nội"
      await tester.enterText(searchBox, 'ha noi');
      await tester.pumpAndSettle();
      expect(find.text('Nhà Phân Phối Hà Nội'), findsOneWidget);
      expect(find.text('Đại Lý Đà Nẵng'), findsNothing);
      expect(find.text('Đồng Tháp Mười'), findsNothing);

      // Test 2: Uppercase "HA NOI" matches "Nhà Phân Phối Hà Nội"
      await tester.enterText(searchBox, 'HA NOI');
      await tester.pumpAndSettle();
      expect(find.text('Nhà Phân Phối Hà Nội'), findsOneWidget);

      // Test 3: "da nang" matches "Đại Lý Đà Nẵng"
      await tester.enterText(searchBox, 'da nang');
      await tester.pumpAndSettle();
      expect(find.text('Đại Lý Đà Nẵng'), findsOneWidget);
      expect(find.text('Nhà Phân Phối Hà Nội'), findsNothing);

      // Test 4: "dong thap" matches "Đồng Tháp Mười"
      await tester.enterText(searchBox, 'dong thap');
      await tester.pumpAndSettle();
      expect(find.text('Đồng Tháp Mười'), findsOneWidget);
      expect(find.text('Đại Lý Đà Nẵng'), findsNothing);

      // Test 5: Phone number search "0987"
      await tester.enterText(searchBox, '0987');
      await tester.pumpAndSettle();
      expect(find.text('Nhà Phân Phối Hà Nội'), findsOneWidget);

      // Test 6: Supplier alphanumeric code search
      await tester.enterText(searchBox, 'NCC');
      await tester.pumpAndSettle();
      expect(find.text('Nhà Phân Phối Hà Nội'), findsOneWidget);
      expect(find.text('Đại Lý Đà Nẵng'), findsOneWidget);
      expect(find.text('Đồng Tháp Mười'), findsOneWidget);

      // Test 7: Non-existent query shows empty state
      await tester.enterText(searchBox, 'khong_ton_tai_xyz');
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy nhà cung cấp'), findsOneWidget);
    });
  });
}
