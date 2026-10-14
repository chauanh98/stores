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
import 'package:stores/domain/repositories/supplier_repository.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';

import 'package:stores/presentation/inventories/widgets/stock_in_item_card.dart';

import '../../support/import_flow_helpers.dart';

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

class _TestSupplierListNotifier extends AutoDisposeAsyncNotifier<List<Supplier>>
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

class _FakeSupplierRepository extends Fake implements SupplierRepository {
  final List<Supplier> suppliers;
  final List<Supplier> upserted = [];
  final List<SupplierDebtTransaction> debtTxs = [];
  _FakeSupplierRepository(this.suppliers);

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async =>
      suppliers.where((s) => s.id == id).firstOrNull;

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    upserted.add(supplier);
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction,
      {String? storeId}) async {
    debtTxs.add(transaction);
  }
}

class _FakeReceiptRepository extends Fake implements StockInReceiptRepository {
  final List<StockInReceipt> saved = [];

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    saved.add(receipt);
  }
}

class _FakeProductRepository implements ProductRepository {
  final List<Product> upsertedProducts = [];
  final List<Product> catalog;
  _FakeProductRepository([this.catalog = const []]);

  @override
  Future<void> upsert(Product product) async {
    upsertedProducts.add(product);
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Product?> fetchById(String id) async =>
      catalog.where((p) => p.id == id).firstOrNull;

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

class _Env {
  final inv = _FakeInventoryRepository();
  late final _FakeProductRepository prod;
  late final _FakeSupplierRepository supplierRepo;
  final receipts = _FakeReceiptRepository();
  _Env(List<Product> products, List<Supplier> suppliers) {
    prod = _FakeProductRepository(products);
    supplierRepo = _FakeSupplierRepository(suppliers);
  }
}

Future<_Env> _pump(
  WidgetTester tester, {
  required UserAccount user,
  required List<Product> products,
  required List<Supplier> suppliers,
}) async {
  final env = _Env(products, suppliers);
  await tester.pumpWidget(
    _buildTestApp(
      child: const ImportInventoryPage(),
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
        productListProvider.overrideWith((ref) => Stream.value(products)),
        supplierListNotifierProvider.overrideWith(
          () => _TestSupplierListNotifier(suppliers),
        ),
        inventoryRepositoryProvider.overrideWithValue(env.inv),
        productRepositoryProvider.overrideWithValue(env.prod),
        completeStockInReceiptUseCaseProvider.overrideWithValue(
          CompleteStockInReceiptUseCase(
            productRepository: env.prod,
            inventoryRepository: env.inv,
            supplierRepository: env.supplierRepo,
            receiptRepository: env.receipts,
          ),
        ),
        availableStoresProvider.overrideWith((ref) async => {
              'store_001': 'Chi nhánh Đông Thắng',
            }),
      ],
    ),
  );
  await tester.pumpAndSettle();
  return env;
}

/// Asserts the completed receipt: stock-in tx recorded, supplier debt
/// increased by [debt] (HN starts at 5.000.000) and totalPurchase += 300.000.
void _expectCompleted(_Env env,
    {required double paid, required double debt, bool checkPaid = true}) {
  expect(env.inv.recordedTransactions.length, 1);
  expect(env.inv.recordedTransactions.first.productId, 'prod_stress_01');
  expect(env.inv.recordedTransactions.first.quantity, 1);
  expect(env.inv.recordedTransactions.first.importPrice, 300000.0);
  expect(env.receipts.saved.length, 1);
  expect(env.receipts.saved.first.totalAmount, 300000.0);
  if (checkPaid) expect(env.receipts.saved.first.paidAmount, paid);
  expect(env.supplierRepo.upserted.length, 1);
  expect(env.supplierRepo.upserted.first.id, 'NCC_HN');
  expect(env.supplierRepo.upserted.first.currentDebt, 5000000.0 + debt);
  expect(env.supplierRepo.upserted.first.totalPurchase, 10300000.0);
  if (debt > 0) {
    expect(env.supplierRepo.debtTxs.length, 1);
    expect(env.supplierRepo.debtTxs.first.supplierId, 'NCC_HN');
    expect(env.supplierRepo.debtTxs.first.amount, debt);
    expect(env.supplierRepo.debtTxs.first.remainingDebt, 5000000.0 + debt);
  } else {
    expect(env.supplierRepo.debtTxs, isEmpty);
  }
}

Future<void> _selectSupplier(WidgetTester tester, String name) async {
  await tester.tap(find.byKey(const Key('select_supplier_btn')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(name));
  await tester.pumpAndSettle();
}

Future<void> _addProductA(WidgetTester tester) => addProductViaSheet(
      tester,
      search: 'Cấu hình Cao',
      productText: 'Sản phẩm Cấu hình Cao',
    );

Future<void> _setPaid(WidgetTester tester, String text) async {
  final f = find.byKey(const Key('input_paid_amount'));
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

/// Supplier + product(1 x 300.000) -> payment step.
Future<void> _toPayment(WidgetTester tester) async {
  await _selectSupplier(tester, 'Nhà Phân Phối Hà Nội');
  await _addProductA(tester);
  await goToPaymentStep(tester);
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
      final env = await _pump(tester,
          user: supervisorUser, products: [productA], suppliers: testSuppliers);
      await _toPayment(tester);
      await tester.tap(find.byKey(const Key('btn_pay_zero')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '300.000 đ');
      await completeReceiptOnPaymentStep(tester);

      _expectCompleted(env, paid: 0.0, debt: 300000.0);
    });

    testWidgets(
        'Boundary 2: Full Paid (0 Debt) results in paidAmount == totalAmount',
        (tester) async {
      final env = await _pump(tester,
          user: supervisorUser, products: [productA], suppliers: testSuppliers);
      await _toPayment(tester);
      // Default: pay in full
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '0 đ');
      await completeReceiptOnPaymentStep(tester);

      _expectCompleted(env, paid: 300000.0, debt: 0.0);
    });

    testWidgets('Boundary 3: Partial payment calculates exact debt difference',
        (tester) async {
      final env = await _pump(tester,
          user: supervisorUser, products: [productA], suppliers: testSuppliers);
      await _toPayment(tester);
      await _setPaid(tester, '120000');
      // Preview displays debt increase 180,000 đ
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '180.000 đ');
      await completeReceiptOnPaymentStep(tester);

      _expectCompleted(env, paid: 120000.0, debt: 180000.0);
    });

    testWidgets(
        'Boundary 4: Overpayment is clamped to totalAmount without generating negative debt',
        (tester) async {
      final env = await _pump(tester,
          user: supervisorUser, products: [productA], suppliers: testSuppliers);
      await _toPayment(tester);
      await _setPaid(tester, '999999999');
      // Debt never negative
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '0 đ');
      await completeReceiptOnPaymentStep(tester);

      // Clamped to 300000.0
      _expectCompleted(env, paid: 300000.0, debt: 0.0);
    },);

    testWidgets(
        'Boundary 4b: Overpayment never reduces the supplier\'s pre-existing debt',
        (tester) async {
      final env = await _pump(tester,
          user: supervisorUser, products: [productA], suppliers: testSuppliers);
      await _toPayment(tester);
      await _setPaid(tester, '999999999');
      await completeReceiptOnPaymentStep(tester);

      // Supplier debt stays at 5.000.000, no debt transaction
      _expectCompleted(env, paid: 300000.0, debt: 0.0, checkPaid: false);
    },);

    testWidgets(
        'Boundary 4c: Overpayment keeps debt non-negative and stock-in is recorded',
        (tester) async {
      final env = await _pump(tester,
          user: supervisorUser, products: [productA], suppliers: testSuppliers);
      await _toPayment(tester);
      await _setPaid(tester, '999999999');
      await completeReceiptOnPaymentStep(tester);

      expect(env.inv.recordedTransactions.length, 1);
      expect(env.inv.recordedTransactions.first.importPrice, 300000.0);
      expect(
          env.supplierRepo.upserted.first.currentDebt, greaterThanOrEqualTo(0));
      expect(env.supplierRepo.debtTxs, isEmpty);
    });

    testWidgets('Boundary 5: Formatted inputs (periods/commas) parse cleanly',
        (tester) async {
      final env = await _pump(tester,
          user: supervisorUser, products: [productA], suppliers: testSuppliers);
      await _toPayment(tester);
      await _setPaid(tester, '150.000');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '150.000 đ');
      await completeReceiptOnPaymentStep(tester);

      _expectCompleted(env, paid: 150000.0, debt: 150000.0);
    });
  });

  group('Milestone 2 Stress: Validation Guards', () {
    testWidgets(
        'Validation: Attempting to complete with debt (Ghi nợ) without supplier is strictly blocked',
        (tester) async {
      final env = await _pump(tester,
          user: supervisorUser, products: [productA], suppliers: testSuppliers);

      // Walk-in: product only, no supplier
      await _addProductA(tester);
      await goToPaymentStep(tester);

      // Pay nothing -> debt without supplier
      await tester.tap(find.byKey(const Key('btn_pay_zero')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '300.000 đ');

      await completeReceiptOnPaymentStep(tester);

      // Blocked with SnackBar
      expect(
          find.byKey(const Key('snackbar_supplier_required')), findsOneWidget);
      expect(find.text('Vui lòng chọn Nhà Cung Cấp để ghi nợ'), findsOneWidget);
      // Zero transactions recorded
      expect(env.inv.recordedTransactions, isEmpty);
      expect(env.receipts.saved, isEmpty);
      expect(env.supplierRepo.upserted, isEmpty);
      expect(env.supplierRepo.debtTxs, isEmpty);
    });
  });

  group('Milestone 2 Stress: Staff Role Masking', () {
    testWidgets(
        'Staff user cannot view unit prices or total values while adding stock',
        (tester) async {
      await _pump(tester,
          user: staffUser, products: [productA], suppliers: testSuppliers);

      expect(find.text('Giá nhập'), findsNothing);
      expect(find.text('Tổng giá trị'), findsNothing);

      await openProductSheet(tester,
          search: 'Cấu hình Cao', productText: 'Sản phẩm Cấu hình Cao');
      expect(find.byKey(const Key('product_edit_sheet')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('btn_sheet_done')));
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      // Item card shows masked values, never the real cost
      expect(find.text('***'), findsWidgets);
      expect(
        find.descendant(
            of: find.byType(StockInItemCard),
            matching: find.textContaining('300.000')),
        findsNothing,
      );
    });

    testWidgets('Staff cannot see the cost total in the bottom summary bar',
        (tester) async {
      await _pump(tester,
          user: staffUser, products: [productA], suppliers: testSuppliers);
      await _addProductA(tester);
      expect(find.byKey(const Key('bottom_bar_total_amount')), findsNothing);
    },);
  });

  group('Milestone 2 Stress: Staff Sheet Masking', () {
    testWidgets(
        'Staff cost-price input is hidden inside the product edit sheet',
        (tester) async {
      await _pump(tester,
          user: staffUser, products: [productA], suppliers: testSuppliers);
      await openProductSheet(tester,
          search: 'Cấu hình Cao', productText: 'Sản phẩm Cấu hình Cao');
      expect(find.byKey(const Key('sheet_input_price')), findsNothing);
      expect(find.textContaining('300.000'), findsNothing);
    },);
  });

  group('Milestone 2 Stress: Diacritic-Free Search in Supplier Selector', () {
    testWidgets(
        'Search matches with unaccented, mixed case, and partial phone/code',
        (tester) async {
      await _pump(tester,
          user: supervisorUser, products: [productA], suppliers: testSuppliers);

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
      expect(find.text('Không tìm thấy Nhà Cung Cấp'), findsOneWidget);
    },);
  });
}
