import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/notifications/notification_dispatcher.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
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
import 'package:stores/domain/repositories/stock_in_receipt_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import '../../support/import_flow_helpers.dart';
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

const _fixtureProduct = Product(
  id: 'prod_01',
  name: 'Sản phẩm Test A',
  code: 'SPA',
  price: 200000,
  costPrice: 150000,
  branchStocks: {'branch_1': 10, 'branch_2': 5},
  category: 'Mỹ phẩm',
);

class _FakeProductRepository implements ProductRepository {
  final List<Product> upsertedProducts = [];

  @override
  Future<void> upsert(Product product) async {
    upsertedProducts.add(product);
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<Product?> fetchById(String id) async =>
      id == 'prod_01' || id == 'SPA' ? _fixtureProduct : null;

  @override
  Future<List<Product>> fetchAll() async => [];

  @override
  Future<void> updateStock(String id, int newStock) async {}

  @override
  Stream<List<Product>> watchAll() => Stream.value([]);
}

/// Supplier repository used by CompleteStockInReceiptUseCase (debt recording
/// now happens inside the use case via upsert + recordDebtTransaction).
class _FakeSupplierRepository implements SupplierRepository {
  final Map<String, Supplier> suppliers;
  final List<Supplier> upserted = [];
  final List<SupplierDebtTransaction> debtTransactions = [];
  _FakeSupplierRepository(List<Supplier> list)
      : suppliers = {for (final s in list) s.id: s};

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async =>
      suppliers[id];

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    upserted.add(supplier);
  }

  @override
  Future<void> recordDebtTransaction(SupplierDebtTransaction transaction,
      {String? storeId}) async {
    debtTransactions.add(transaction);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Inert notification repository so no Firebase access happens on completion.
class _FakeNotificationRepository implements NotificationRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<void>.value();
}

class _FakeReceiptRepository implements StockInReceiptRepository {
  final List<StockInReceipt> saved = [];

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    saved.add(receipt);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

    test(
        'InventoryTransaction entity holds supplierId, supplierName, and importCode',
        () {
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

    test(
        'InventoryTransactionModel serializes and deserializes supplier fields',
        () {
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
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value([sampleProduct])),
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

  group('ImportInventoryPage Payment Option & Live Debt Preview Tests (R2)',
      () {
    testWidgets(
        'Supervisor sees payment options, partial payment input, and live debt increase preview',
        (tester) async {
      final supplierNotifier =
          _TestSupplierListNotifier([sampleSupplier1, sampleSupplier2]);

      await tester.pumpWidget(
        _buildTestApp(
          child: const ImportInventoryPage(),
          overrides: [
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => supplierNotifier),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Step 0: supplier + product (via modal sheet), then continue.
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Công ty Cổ phần Digiworld'));
      await tester.pumpAndSettle();
      await addProductViaSheet(tester,
          search: 'Test', productText: 'Sản phẩm Test A');
      await goToPaymentStep(tester);

      // Payment options exist
      expect(find.text('Hình thức thanh toán'), findsOneWidget);
      expect(find.byKey(const Key('payment_cash')), findsOneWidget);
      expect(find.byKey(const Key('payment_transfer')), findsOneWidget);
      expect(find.byKey(const Key('payment_card')), findsOneWidget);
      expect(find.byKey(const Key('btn_pay_in_full')), findsOneWidget);
      expect(find.byKey(const Key('btn_pay_zero')), findsOneWidget);
      expect(find.byKey(const Key('toggle_debt_accounting')), findsOneWidget);
      expect(find.byKey(const Key('input_paid_amount')), findsOneWidget);
      expect(find.text('Tính vào công nợ:'), findsOneWidget);

      // Supplier selected on step 0 is carried into the dropdown
      expect(find.textContaining('Công ty Cổ phần Digiworld (NCC000001)'),
          findsWidgets);

      // costPrice 150000 x 1 -> net payable 150.000 đ, default full payment -> no debt
      expect(find.text('150.000 đ'), findsWidgets);
      expect(
          tester.widget<Text>(find.byKey(const Key('text_net_payable'))).data,
          '150.000 đ');
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '0 đ');

      // 'Ghi nợ' (pay zero) -> whole amount becomes debt
      await tester.ensureVisible(find.byKey(const Key('btn_pay_zero')));
      await tester.tap(find.byKey(const Key('btn_pay_zero')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '150.000 đ');

      // Enter partial payment of 50000 đ -> live debt = 100.000 đ
      await tester.ensureVisible(find.byKey(const Key('input_paid_amount')));
      await tester.enterText(
          find.byKey(const Key('input_paid_amount')), '50000');
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '100.000 đ');
      expect(
          tester.widget<Text>(find.byKey(const Key('text_net_payable'))).data,
          '150.000 đ');

      // 'Trả đủ' restores zero debt
      await tester.tap(find.byKey(const Key('btn_pay_in_full')));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<Text>(find.byKey(const Key('text_remaining_debt')))
              .data,
          '0 đ');
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
            productListProvider
                .overrideWith((ref) => Stream.value([sampleProduct])),
            supplierListNotifierProvider.overrideWith(() => supplierNotifier),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Thới Bình',
                }),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Công ty Cổ phần Digiworld'));
      await tester.pumpAndSettle();

      // Staff: sheet has no unit-price input (cost price hidden)
      await openProductSheet(tester,
          search: 'Test', productText: 'Sản phẩm Test A');
      expect(find.byKey(const Key('product_edit_sheet')), findsOneWidget);
      expect(find.byKey(const Key('sheet_input_price')), findsNothing);
      expect(find.textContaining('150.000'), findsNothing);
      await tester.ensureVisible(find.byKey(const Key('btn_sheet_done')));
      await tester.tap(find.byKey(const Key('btn_sheet_done')));
      await tester.pumpAndSettle();

      // Step 0 for staff must not leak cost figures
      expect(find.textContaining('150.000'), findsNothing);
      expect(find.textContaining('Giá nhập'), findsNothing);

      await goToPaymentStep(tester);

      // Step 1 for staff: no cost price / totals / paid amount leaked
      expect(find.byKey(const Key('input_paid_amount')), findsNothing);
      expect(find.byKey(const Key('text_total_goods_amount')), findsNothing);
      expect(find.textContaining('150.000'), findsNothing);
      expect(find.textContaining('Giá nhập'), findsNothing);
    });
  });

  group('ImportInventoryPage Save & recordImportDebt Execution Tests (R2)', () {
    late _FakeInventoryRepository fakeInventoryRepo;
    late _FakeProductRepository fakeProductRepo;
    late _FakeReceiptRepository fakeReceiptRepo;
    late _FakeSupplierRepository fakeSupplierRepo;

    List<Override> overridesFor(UserAccount user) => [
          authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
          productListProvider
              .overrideWith((ref) => Stream.value([sampleProduct])),
          supplierListNotifierProvider.overrideWith(() =>
              _TestSupplierListNotifier([sampleSupplier1, sampleSupplier2])),
          inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
          productRepositoryProvider.overrideWithValue(fakeProductRepo),
          supplierRepositoryProvider.overrideWithValue(fakeSupplierRepo),
          stockInReceiptRepositoryProvider.overrideWithValue(fakeReceiptRepo),
          notificationRepositoryProvider
              .overrideWithValue(_FakeNotificationRepository()),
          notificationDispatcherProvider.overrideWith(
              (ref) => NotificationDispatcher(_FakeNotificationRepository())),
          availableStoresProvider.overrideWith((ref) async => {
                'store_001': 'Chi nhánh Thới Bình',
              }),
        ];

    setUp(() {
      fakeInventoryRepo = _FakeInventoryRepository();
      fakeProductRepo = _FakeProductRepository();
      fakeReceiptRepo = _FakeReceiptRepository();
      fakeSupplierRepo =
          _FakeSupplierRepository([sampleSupplier1, sampleSupplier2]);
    });

    testWidgets(
        'Supervisor saves with debt payment triggers recordImportDebt and tags InventoryTransaction',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(
        child: const ImportInventoryPage(),
        overrides: overridesFor(supervisorUser),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Công ty Cổ phần Digiworld'));
      await tester.pumpAndSettle();
      await addProductViaSheet(tester,
          search: 'Test', productText: 'Sản phẩm Test A');
      await goToPaymentStep(tester);

      await tester.ensureVisible(find.byKey(const Key('input_paid_amount')));
      await tester.enterText(
          find.byKey(const Key('input_paid_amount')), '50000');
      await tester.pumpAndSettle();

      await completeReceiptOnPaymentStep(tester);

      // Debt recorded through the supplier repository (importBill, 100k)
      expect(fakeSupplierRepo.debtTransactions.length, 1);
      final debtTx = fakeSupplierRepo.debtTransactions.first;
      expect(debtTx.supplierId, 'NCC000001');
      expect(debtTx.type, SupplierDebtType.importBill);
      expect(debtTx.amount, 100000.0); // 150000 total - 50000 paid
      expect(debtTx.remainingDebt, 25000000 + 100000.0);
      expect(debtTx.referenceCode, isNotNull);
      expect(debtTx.referenceCode.toString(), startsWith('PN_'));

      // Supplier balance updated: debt + remaining, totalPurchase + net payable
      expect(fakeSupplierRepo.upserted.length, 1);
      expect(fakeSupplierRepo.upserted.first.currentDebt, 25100000.0);
      expect(fakeSupplierRepo.upserted.first.totalPurchase, 100150000.0);

      // InventoryTransaction tagged with supplier info
      expect(fakeInventoryRepo.recordedTransactions.length, 1);
      final invTx = fakeInventoryRepo.recordedTransactions.first;
      expect(invTx.supplierId, 'NCC000001');
      expect(invTx.supplierName, 'Công ty Cổ phần Digiworld');
      expect(invTx.importCode, debtTx.referenceCode);
      expect(invTx.quantity, 1);
      expect(invTx.importPrice, 150000.0);

      // Receipt persisted as completed with paid amount
      expect(fakeReceiptRepo.saved.length, 1);
      expect(fakeReceiptRepo.saved.first.status, 'completed');
      expect(fakeReceiptRepo.saved.first.paidAmount, 50000.0);

      // Product stock updated
      expect(fakeProductRepo.upsertedProducts.length, 1);
      expect(
          fakeProductRepo.upsertedProducts.first.branchStocks['branch_1'], 11);
    });

    testWidgets(
        'Staff saves with Ghi nợ NCC (100%) computes debt from costPrice',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(
        child: const ImportInventoryPage(),
        overrides: overridesFor(staffUser),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Công ty TNHH Synnex FPT'));
      await tester.pumpAndSettle();
      await addProductViaSheet(tester,
          search: 'Test', productText: 'Sản phẩm Test A');
      await goToPaymentStep(tester);

      // Staff cannot type amounts: the 'Ghi nợ' (100% debt) quick action is the
      // only way to record full debt.
      await tester.ensureVisible(find.byKey(const Key('btn_pay_zero')));
      await tester.tap(find.byKey(const Key('btn_pay_zero')));
      await tester.pumpAndSettle();

      await completeReceiptOnPaymentStep(tester);

      // Debt computed from costPrice (150000), nothing paid
      expect(fakeSupplierRepo.debtTransactions.length, 1);
      final debtTx = fakeSupplierRepo.debtTransactions.first;
      expect(debtTx.supplierId, 'NCC000002');
      expect(debtTx.amount, 150000.0);
      expect(fakeSupplierRepo.upserted.first.currentDebt, 150000.0);
      expect(fakeReceiptRepo.saved.first.paidAmount, 0.0);

      expect(fakeInventoryRepo.recordedTransactions.length, 1);
      final invTx = fakeInventoryRepo.recordedTransactions.first;
      expect(invTx.supplierId, 'NCC000002');
      expect(invTx.supplierName, 'Công ty TNHH Synnex FPT');
      expect(invTx.importPrice, 150000.0);
    });

    testWidgets(
        'Blocks save and shows warning if Ghi nợ NCC is selected without a supplier',
        (tester) async {
      await tester.pumpWidget(_buildTestApp(
        child: const ImportInventoryPage(),
        overrides: overridesFor(supervisorUser),
      ));
      await tester.pumpAndSettle();

      // Product but NO supplier
      await addProductViaSheet(tester,
          search: 'Test', productText: 'Sản phẩm Test A');
      await goToPaymentStep(tester);

      // Choose debt (pay zero) without supplier
      await tester.ensureVisible(find.byKey(const Key('btn_pay_zero')));
      await tester.tap(find.byKey(const Key('btn_pay_zero')));
      await tester.pumpAndSettle();

      await completeReceiptOnPaymentStep(tester);

      // SnackBar displayed
      expect(
          find.byKey(const Key('snackbar_supplier_required')), findsOneWidget);
      expect(find.text('Vui lòng chọn Nhà Cung Cấp để ghi nợ'), findsOneWidget);

      // Still on payment step; nothing committed
      expect(find.byKey(const Key('btn_payment_complete')), findsOneWidget);
      expect(fakeInventoryRepo.recordedTransactions, isEmpty);
      expect(fakeSupplierRepo.debtTransactions, isEmpty);
      expect(fakeSupplierRepo.upserted, isEmpty);
      expect(fakeReceiptRepo.saved, isEmpty);
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
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Check supplier and import code rows
      expect(find.text('Nhà cung cấp'), findsOneWidget);
      expect(
          find.text('Công ty Cổ phần Digiworld (NCC000001)'), findsOneWidget);
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
            authProvider
                .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
            productListProvider
                .overrideWith((ref) => Stream.value([sampleProduct])),
            importsFilteredProvider
                .overrideWith((ref) => Stream.value([txWithSupplier])),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
          ],
        ),
      );
      await tester.pumpAndSettle();

      // Check tile displays product name and supplier info
      expect(find.text('Sản phẩm Test A'), findsOneWidget);
      expect(
          find.textContaining('NCC: Synnex FPT (NCC000002)'), findsOneWidget);
    });
  });
}
