import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/stock_in_receipt.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_item_card.dart';

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

  _TestSupplierListNotifier(this.initialData);

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
  }) async {}
}

Widget _buildTestApp({
  required Widget child,
  List<Supplier>? suppliers,
  List<Product>? products,
}) {
  const testUser = UserAccount(
    username: 'admin',
    displayName: 'Admin User',
    role: 'admin',
    storeId: 'store_001',
  );

  final testSuppliers = suppliers ??
      [
        const Supplier(
          id: 'sup_01',
          code: 'NCC001',
          name: 'Công ty Cổ phần Digiworld',
          phone: '0901234567',
          currentDebt: 0.0,
          totalPurchase: 10000000.0,
        ),
      ];

  final testProducts = products ??
      [
        const Product(
          id: 'prod_1',
          name: 'Ghế cafe sân vườn',
          code: 'BGCF1',
          price: 2580000,
          costPrice: 1290000,
          branchStocks: {'store_001': 5},
          category: 'Bàn ghế',
        ),
      ];

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      productListProvider.overrideWith((ref) => Stream.value(testProducts)),
      supplierListNotifierProvider.overrideWith(
        () => _TestSupplierListNotifier(testSuppliers),
      ),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
          }),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  group('Import Inventory UI Polish & Alignment Tests', () {
    testWidgets('1. Only single save draft button exists (no duplicate in AppBar)', (tester) async {
      await tester.pumpWidget(_buildTestApp(child: const ImportInventoryPage()));
      await tester.pumpAndSettle();

      // Verify no duplicate save draft icon button in AppBar
      expect(find.byKey(const Key('btn_appbar_save_draft')), findsNothing);

      // Verify single prominent save draft button in sticky bottom bar
      expect(find.byKey(const Key('btn_save_draft')), findsOneWidget);
    });

    testWidgets('2. Product search bar displays clear button (X) when text is entered and clears on tap', (tester) async {
      await tester.pumpWidget(_buildTestApp(child: const ImportInventoryPage()));
      await tester.pumpAndSettle();

      final searchField = find.byType(TextFormField).first;
      expect(find.byKey(const Key('btn_clear_product_search')), findsNothing);

      // Enter search text
      await tester.enterText(searchField, 'Ghế cafe');
      await tester.pumpAndSettle();

      // Clear button (X) is now visible
      expect(find.byKey(const Key('btn_clear_product_search')), findsOneWidget);

      // Tap clear button
      await tester.tap(find.byKey(const Key('btn_clear_product_search')));
      await tester.pumpAndSettle();

      // Text is cleared and clear button disappears
      expect(find.text('Ghế cafe'), findsNothing);
      expect(find.byKey(const Key('btn_clear_product_search')), findsNothing);
    });

    testWidgets('3. Supplier card displays "Bỏ chọn" horizontally aligned with "Nhà cung cấp" header', (tester) async {
      final initialDraft = StockInReceipt(
        id: 'draft_01',
        importCode: 'PN_01',
        date: DateTime.now(),
        storeId: 'store_001',
        supplierId: 'sup_01',
        supplierName: 'Công ty Cổ phần Digiworld',
        items: const [],
      );

      await tester.pumpWidget(_buildTestApp(
        child: ImportInventoryPage(initialReceipt: initialDraft),
      ));
      await tester.pumpAndSettle();

      // Both "Nhà cung cấp" and "Bỏ chọn" exist
      expect(find.text('Nhà cung cấp'), findsOneWidget);
      expect(find.text('Bỏ chọn'), findsOneWidget);

      // Verify they are horizontally aligned on the same row (within 4 pixels dy)
      final nhaCungCapPos = tester.getCenter(find.text('Nhà cung cấp'));
      final boChonPos = tester.getCenter(find.text('Bỏ chọn'));
      expect((nhaCungCapPos.dy - boChonPos.dy).abs(), lessThan(4.0));

      // Tap "Bỏ chọn" -> supplier is cleared
      await tester.tap(find.text('Bỏ chọn'));
      await tester.pumpAndSettle();

      expect(find.text('Chưa chọn Nhà Cung Cấp (Bấm để chọn)'), findsOneWidget);
      expect(find.text('Bỏ chọn'), findsNothing);
    });

    testWidgets('4. Supplier select modal has clean "Thêm mới NCC" without duplicate plus sign', (tester) async {
      await tester.pumpWidget(_buildTestApp(child: const ImportInventoryPage()));
      await tester.pumpAndSettle();

      // Tap supplier selector card to open bottom sheet
      await tester.tap(find.byKey(const Key('select_supplier_btn')));
      await tester.pumpAndSettle();

      expect(find.text('Chọn Nhà Cung Cấp'), findsOneWidget);
      expect(find.text('Thêm mới NCC'), findsOneWidget);
      expect(find.byKey(const Key('quick_add_supplier_btn')), findsOneWidget);
      expect(find.text('+ Thêm nhanh NCC'), findsNothing); // No duplicate plus
    });

    testWidgets('5. StockInItemCard has clean subtitle without duplicate stock and price text', (tester) async {
      const item = StockInReceiptItem(
        transactionId: 't1',
        productId: 'prod_1',
        quantity: 2,
        unitPrice: 1290000,
        originalPrice: 1290000,
        productName: 'Ghế cafe sân vườn - nhôm đúc',
        productCode: 'BGCF1',
      );

      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: StockInItemCard(
            item: item,
            currentStock: 5,
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Ghế cafe sân vườn - nhôm đúc'), findsOneWidget);
      expect(find.text('Mã: BGCF1 • Tồn kho: 5'), findsOneWidget);
      expect(find.text('Đơn giá: 1.290.000 đ'), findsOneWidget);
      expect(find.text('2.580.000 đ'), findsOneWidget);
      // No duplicate 'Tồn kho: 5 • Giá: 1.290.000 đ'
      expect(find.text('Tồn kho: 5 • Giá: 1.290.000 đ'), findsNothing);
    });
  });
}
