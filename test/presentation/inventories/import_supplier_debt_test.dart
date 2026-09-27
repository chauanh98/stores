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
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/data/models/inventory_transaction_model.dart';
import 'package:stores/presentation/inventories/pages/import_detail_page.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/imports_page.dart';

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
  const supervisorUser = UserAccount(
    username: 'supervisor_01',
    displayName: 'Giám sát viên',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const sampleProduct = Product(
    id: 'prod_01',
    name: 'Sản phẩm Test A',
    code: 'SPA',
    price: 200000,
    costPrice: 150000,
    branchStocks: {'branch_1': 10, 'branch_2': 5},
    category: 'Mỹ phẩm',
  );

  const sampleSupplier1 = Supplier(
    id: 'NCC000001',
    code: 'NCC000001',
    name: 'Công ty Cổ phần Digiworld',
    phone: '02839291234',
    email: 'contact@digiworld.com.vn',
    address: '195 Cô Bắc, Quận 1, TP. HCM',
    taxCode: '0302861742',
    totalPurchase: 100000000,
    currentDebt: 25000000,
    status: 'active',
  );

  const sampleSupplier2 = Supplier(
    id: 'NCC000002',
    code: 'NCC000002',
    name: 'Công ty TNHH Synnex FPT',
    phone: '02473006666',
    email: 'distribution@synnexfpt.com.vn',
    address: 'Cầu Giấy, Hà Nội',
    taxCode: '0103636585',
    totalPurchase: 50000000,
    currentDebt: 0,
    status: 'active',
  );

  group('Domain & Model Extension Tests (R2)', () {
    test('SupplierDebtTypeExtension.fromDbValue supports import_debt', () {
      expect(SupplierDebtTypeExtension.fromDbValue('import_debt'),
          SupplierDebtType.importBill);
      expect(SupplierDebtTypeExtension.fromDbValue('importdebt'),
          SupplierDebtType.importBill);
      expect(SupplierDebtTypeExtension.fromDbValue('IMPORT_DEBT'),
          SupplierDebtType.importBill);
      expect(SupplierDebtTypeExtension.fromDbValue('import'),
          SupplierDebtType.importBill);
      expect(SupplierDebtTypeExtension.fromDbValue('payment'),
          SupplierDebtType.payment);
    });

    test('InventoryTransaction entity holds supplierId, supplierName, and importCode', () {
      final tx = InventoryTransaction(
        id: 'tx_001',
        productId: 'prod_01',
        type: TransactionType.import,
        quantity: 10,
        date: DateTime(2026, 9, 13),
        note: 'Nhập hàng',
        importPrice: 150000,
        supplierId: 'NCC000001',
        supplierName: 'Công ty Cổ phần Digiworld',
        importCode: 'PN_1726200000',
      );

      expect(tx.supplierId, 'NCC000001');
      expect(tx.supplierName, 'Công ty Cổ phần Digiworld');
      expect(tx.importCode, 'PN_1726200000');

      final copied = tx.copyWith(
        supplierName: 'Công ty Cổ phần Digiworld Mới',
        quantity: 20,
      );
      expect(copied.supplierId, 'NCC000001');
      expect(copied.supplierName, 'Công ty Cổ phần Digiworld Mới');
      expect(copied.importCode, 'PN_1726200000');
      expect(copied.quantity, 20);
    });

    test('InventoryTransactionModel serializes and deserializes supplier fields', () {
      final tx = InventoryTransaction(
        id: 'tx_002',
        productId: 'prod_02',
        type: TransactionType.import,
        quantity: 5,
        date: DateTime(2026, 9, 13, 10, 0, 0),
        note: 'Nhập test serialization',
        importPrice: 120000,
        supplierId: 'NCC000002',
        supplierName: 'Synnex FPT',
        importCode: 'PN_99999',
      );

      final model = InventoryTransactionModel.fromEntity(tx);
      expect(model.supplierId, 'NCC000002');
      expect(model.supplierName, 'Synnex FPT');
      expect(model.importCode, 'PN_99999');

      final map = model.toMap();
      expect(map['supplierId'], 'NCC000002');
      expect(map['supplierName'], 'Synnex FPT');
      expect(map['importCode'], 'PN_99999');

      final fromMapModel = InventoryTransactionModel.fromMap(map);
      expect(fromMapModel.supplierId, 'NCC000002');
      expect(fromMapModel.supplierName, 'Synnex FPT');
      expect(fromMapModel.importCode, 'PN_99999');

      final restoredEntity = fromMapModel.toEntity();
      expect(restoredEntity.supplierId, 'NCC000002');
      expect(restoredEntity.supplierName, 'Synnex FPT');
      expect(restoredEntity.importCode, 'PN_99999');
    });
  });

  group('ImportInventoryPage Supplier Selection & Quick-Add Tests (R2)', () {
    testWidgets('Displays Supplier Selector Card and opens sheet with search',
        (tester) async {
      final supplierNotifier =
          _TestSupplierListNotifier([sampleSupplier1, sampleSupplier2]);

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => supplierNotifier),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Verify unselected supplier card
      expect(find.text('Nhà cung cấp'), findsOneWidget);
      expect(find.text('Chưa chọn Nhà Cung Cấp (Bấm để chọn)'), findsOneWidget);

      // Tap on supplier selector card to open bottom sheet
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();

      // Bottom sheet header and quick-add button
      expect(find.text('Chọn Nhà Cung Cấp'), findsOneWidget);
      expect(find.text('Thêm mới NCC'), findsOneWidget);
      expect(find.byKey(const Key('quick_add_supplier_btn')), findsOneWidget);

      // Verify suppliers listed
      expect(find.text('Công ty Cổ phần Digiworld'), findsOneWidget);
      expect(find.text('Công ty TNHH Synnex FPT'), findsOneWidget);

      // Test real-time search filtering
      await tester.enterText(
          find.byKey(const Key('supplier_search_field')), 'Synnex');
      await tester.pumpAndSettle();

      expect(find.text('Công ty TNHH Synnex FPT'), findsOneWidget);
      expect(find.text('Công ty Cổ phần Digiworld'), findsNothing);

      // Select Synnex FPT
      await tester.tap(find.text('Công ty TNHH Synnex FPT'));
      await tester.pumpAndSettle();

      // Verify bottom sheet closed and selected supplier card updated
      expect(find.text('Công ty TNHH Synnex FPT'), findsOneWidget);
      expect(find.text('NCC000002'), findsOneWidget);
      expect(find.text('Không có nợ'), findsOneWidget);
      expect(find.text('Bỏ chọn'), findsOneWidget);

      // Tap 'Bỏ chọn' to clear
      await tester.tap(find.text('Bỏ chọn'));
      await tester.pumpAndSettle();
      expect(find.text('Chưa chọn Nhà Cung Cấp (Bấm để chọn)'), findsOneWidget);
    });
  });

  group('ImportInventoryPage Payment Option & Live Debt Preview Tests (R2)', () {
    testWidgets(
        'Supervisor sees payment options, partial payment input, and live debt increase preview',
        (tester) async {
      final supplierNotifier =
          _TestSupplierListNotifier([sampleSupplier1, sampleSupplier2]);

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => supplierNotifier),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select product
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Test');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Test A').last);
      await tester.pumpAndSettle();

      // Payment options exist
      expect(find.text('Hình thức thanh toán'), findsOneWidget);
      expect(find.text('Thanh toán toàn bộ'), findsOneWidget);
      expect(find.text('Ghi nợ NCC'), findsOneWidget);

      // Select supplier 1 (Digiworld - current debt 25M)
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Công ty Cổ phần Digiworld'));
      await tester.pumpAndSettle();

      // Switch to 'Ghi nợ NCC'
      await tester.ensureVisible(find.text('Ghi nợ NCC'));
      await tester.tap(find.text('Ghi nợ NCC'));
      await tester.pumpAndSettle();

      // Verify paid amount field and live preview appear
      await tester.ensureVisible(find.byKey(const Key('paid_amount_field')));
      expect(find.byKey(const Key('paid_amount_field')), findsOneWidget);
      expect(find.text('Chi tiết công nợ phát sinh:'), findsOneWidget);
      expect(find.text('Ghi nhận nợ NCC:'), findsOneWidget);
      expect(find.text('Nợ cũ NCC:'), findsOneWidget);
      expect(find.text('Dư nợ mới sau nhập:'), findsOneWidget);

      // Product has costPrice 150000, quantity 1 -> total is 150.000 đ
      // Initially paid amount is 0, so debt increase is 150.000 đ
      expect(find.textContaining('150.000'), findsWidgets);

      // Enter partial payment of 50000 đ
      await tester.enterText(
          find.byKey(const Key('paid_amount_field')), '50000');
      await tester.pumpAndSettle();

      // Live debt preview updates: 150000 - 50000 = 100000 đ debt increase
      expect(find.textContaining('100.000'), findsWidgets);
    });

    testWidgets('Staff sees masked payment options without cost prices',
        (tester) async {
      final supplierNotifier =
          _TestSupplierListNotifier([sampleSupplier1, sampleSupplier2]);

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => supplierNotifier),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Staff sees 100% debt label and automatic background calculation subtext
      expect(find.text('Thanh toán toàn bộ'), findsOneWidget);
      expect(find.text('Ghi nợ NCC (100%)'), findsOneWidget);
      expect(
          find.text('Đơn vị tính giá vốn tự động theo định mức hệ thống'),
          findsOneWidget);

      // Switch to 'Ghi nợ NCC (100%)'
      await tester.ensureVisible(find.text('Ghi nợ NCC (100%)'));
      await tester.tap(find.text('Ghi nợ NCC (100%)'));
      await tester.pumpAndSettle();

      // Paid amount field must NOT be visible for staff
      expect(find.byKey(const Key('paid_amount_field')), findsNothing);
      expect(find.text('Chi tiết công nợ phát sinh:'), findsNothing);
      // Sensitive price figures must NOT be displayed
      expect(find.textContaining('Giá nhập'), findsNothing);
      expect(find.textContaining('Tổng giá trị'), findsNothing);
    });
  });

  group('ImportInventoryPage Save & recordImportDebt Execution Tests (R2)', () {
    testWidgets(
        'Supervisor saves with debt payment triggers recordImportDebt and tags InventoryTransaction',
        (tester) async {
      final recordedImportDebts = <Map<String, dynamic>>[];
      final fakeInventoryRepo = _FakeInventoryRepository();
      final fakeProductRepo = _FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(
                  [sampleSupplier1, sampleSupplier2], recordedImportDebts),
            ),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            productRepositoryProvider.overrideWithValue(fakeProductRepo),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select product
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Test');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Test A').last);
      await tester.pumpAndSettle();

      // Select supplier Digiworld
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Công ty Cổ phần Digiworld'));
      await tester.pumpAndSettle();

      // Choose debt payment and set partial payment
      await tester.ensureVisible(find.text('Ghi nợ NCC'));
      await tester.tap(find.text('Ghi nợ NCC'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('paid_amount_field')));
      await tester.enterText(
          find.byKey(const Key('paid_amount_field')), '50000');
      await tester.pumpAndSettle();

      // Tap Save in AppBar
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Verify recordImportDebt was invoked
      expect(recordedImportDebts.length, 1);
      final debtRecord = recordedImportDebts.first;
      expect(debtRecord['supplierId'], 'NCC000001');
      expect(debtRecord['totalAmount'], 150000.0);
      expect(debtRecord['paidAmount'], 50000.0);
      expect(debtRecord['importCode'], isNotNull);
      expect(debtRecord['importCode'].toString(), startsWith('PN_'));

      // Verify InventoryTransaction was recorded with supplier info
      expect(fakeInventoryRepo.recordedTransactions.length, 1);
      final invTx = fakeInventoryRepo.recordedTransactions.first;
      expect(invTx.supplierId, 'NCC000001');
      expect(invTx.supplierName, 'Công ty Cổ phần Digiworld');
      expect(invTx.importCode, debtRecord['importCode']);
      expect(invTx.quantity, 1);
      expect(invTx.importPrice, 150000.0);

      // Verify product stock and cost price updated
      expect(fakeProductRepo.upsertedProducts.length, 1);
      expect(fakeProductRepo.upsertedProducts.first.branchStocks['branch_1'], 11);
    });

    testWidgets('Staff saves with Ghi nợ NCC (100%) computes debt from costPrice',
        (tester) async {
      final recordedImportDebts = <Map<String, dynamic>>[];
      final fakeInventoryRepo = _FakeInventoryRepository();
      final fakeProductRepo = _FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(
              () => _TestSupplierListNotifier(
                  [sampleSupplier1, sampleSupplier2], recordedImportDebts),
            ),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            productRepositoryProvider.overrideWithValue(fakeProductRepo),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select product
      final searchField = find.widgetWithText(TextFormField, 'Tìm kiếm sản phẩm');
      await tester.tap(searchField);
      await tester.enterText(searchField, 'Test');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('Sản phẩm Test A').last);
      await tester.pumpAndSettle();

      // Select Synnex FPT
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Công ty TNHH Synnex FPT'));
      await tester.pumpAndSettle();

      // Select 'Ghi nợ NCC (100%)'
      await tester.ensureVisible(find.text('Ghi nợ NCC (100%)'));
      await tester.tap(find.text('Ghi nợ NCC (100%)'));
      await tester.pumpAndSettle();

      // Tap Save
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // Verify recordImportDebt: totalAmount computed from costPrice (150000), paidAmount is 0
      expect(recordedImportDebts.length, 1);
      final debtRecord = recordedImportDebts.first;
      expect(debtRecord['supplierId'], 'NCC000002');
      expect(debtRecord['totalAmount'], 150000.0);
      expect(debtRecord['paidAmount'], 0.0);

      // InventoryTransaction includes supplierId & supplierName
      expect(fakeInventoryRepo.recordedTransactions.length, 1);
      final invTx = fakeInventoryRepo.recordedTransactions.first;
      expect(invTx.supplierId, 'NCC000002');
      expect(invTx.supplierName, 'Công ty TNHH Synnex FPT');
    });

    testWidgets(
        'Blocks save and shows warning if Ghi nợ NCC is selected without a supplier',
        (tester) async {
      final supplierNotifier =
          _TestSupplierListNotifier([sampleSupplier1, sampleSupplier2]);
      final fakeInventoryRepo = _FakeInventoryRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => supplierNotifier),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Select 'Ghi nợ NCC' WITHOUT selecting supplier
      await tester.ensureVisible(find.text('Ghi nợ NCC'));
      await tester.tap(find.text('Ghi nợ NCC'));
      await tester.pumpAndSettle();

      // Warning banner displayed
      expect(find.textContaining('Vui lòng chọn NCC để ghi nợ'), findsOneWidget);

      // Tap Save
      await tester.tap(find.byIcon(Icons.save));
      await tester.pumpAndSettle();

      // SnackBar displayed
      expect(find.text('Vui lòng chọn Nhà Cung Cấp để ghi nợ'), findsOneWidget);

      // No inventory transactions or debt records committed
      expect(fakeInventoryRepo.recordedTransactions, isEmpty);
      expect(supplierNotifier.recordedImportDebts, isEmpty);
    });
  });

  group('ImportDetailPage & ImportsPage Supplier Display Tests (R2)', () {
    testWidgets('ImportDetailPage displays supplier name, code, and importCode',
        (tester) async {
      final txWithSupplier = InventoryTransaction(
        id: 'tx_with_supplier_01',
        productId: 'prod_01',
        type: TransactionType.import,
        quantity: 8,
        date: DateTime(2026, 9, 13),
        note: 'Nhập lô hàng linh kiện',
        importPrice: 150000,
        createdBy: 'supervisor_01',
        createdByName: 'Giám sát viên',
        supplierId: 'NCC000001',
        supplierName: 'Công ty Cổ phần Digiworld',
        importCode: 'PN_1726200000',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: ImportDetailPage(
            tx: txWithSupplier,
            product: sampleProduct,
          ),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Check supplier and import code rows
      expect(find.text('Nhà cung cấp'), findsOneWidget);
      expect(find.text('Công ty Cổ phần Digiworld (NCC000001)'), findsOneWidget);
      expect(find.text('Mã lô nhập'), findsOneWidget);
      expect(find.text('PN_1726200000'), findsOneWidget);
    });

    testWidgets('ImportsPage list tile displays supplier name and code',
        (tester) async {
      final txWithSupplier = InventoryTransaction(
        id: 'tx_tile_01',
        productId: 'prod_01',
        type: TransactionType.import,
        quantity: 12,
        date: DateTime(2026, 9, 13),
        note: 'Nhập hàng',
        supplierId: 'NCC000002',
        supplierName: 'Synnex FPT',
      );

      final fakeInventoryRepo = _FakeInventoryRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportsPage(),
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
            importsFilteredProvider.overrideWith((ref) => Stream.value([txWithSupplier])),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Check tile displays product name and supplier info
      expect(find.text('Sản phẩm Test A'), findsOneWidget);
      expect(find.textContaining('NCC: Synnex FPT (NCC000002)'), findsOneWidget);
    });
  });
}
