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
import 'package:stores/presentation/inventories/widgets/stock_in_payment_confirmation_view.dart';
import 'package:stores/presentation/inventories/widgets/stock_in_product_edit_sheet.dart';

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
          name: 'Công ty TNHH Ánh Dương',
          code: 'NCC001',
          phone: '0912345678',
        ),
      ];

  final testProducts = products ??
      [
        const Product(
          id: 'prod_01',
          name: 'Bao bì 5kg',
          code: 'SP001',
          price: 50000,
          costPrice: 30000,
          branchStocks: {'store_001': 10},
          category: 'Bao bì',
        ),
        const Product(
          id: 'prod_02',
          name: 'Gạo ST25',
          code: 'SP002',
          price: 180000,
          costPrice: 150000,
          branchStocks: {'store_001': 20},
          category: 'Gạo',
        ),
      ];

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      availableStoresProvider.overrideWith((ref) async => {'store_001': 'Chi nhánh Đông Thắng'}),
      supplierListNotifierProvider.overrideWith(
        () => _TestSupplierListNotifier(testSuppliers),
      ),
      productListProvider.overrideWith(
        (ref) => Stream.value(testProducts),
      ),
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    ),
  );
}

void main() {
  group('Draft Resumption Dynamic Total & Payment Recalculation Tests', () {
    testWidgets(
      'Resuming draft and increasing quantity updates Step 2 payment and net payable',
      (tester) async {
        final initialReceipt = StockInReceipt(
          id: 'PN_DRAFT_001',
          importCode: 'PN0001',
          date: DateTime.now(),
          storeId: 'store_001',
          supplierId: 'sup_01',
          supplierName: 'Công ty TNHH Ánh Dương',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_01',
              productId: 'prod_01',
              productName: 'Bao bì 5kg',
              productCode: 'SP001',
              quantity: 1,
              unitPrice: 30000,
              originalPrice: 30000,
              discount: 0,
            ),
          ],
          totalAmount: 30000,
          paidAmount: 30000, // paid in full
          discount: 0,
          status: 'draft',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: ImportInventoryPage(initialReceipt: initialReceipt),
          ),
        );
        await tester.pumpAndSettle();

        // Total should initially be 30.000 đ
        expect(find.text('30.000 đ'), findsWidgets);

        // Tap increment button on item card to increase quantity to 2
        final incBtn = find.byKey(const Key('stepper_inc_prod_01'));
        expect(incBtn, findsOneWidget);
        await tester.tap(incBtn);
        await tester.pumpAndSettle();

        // New total goods should be 60.000 đ
        expect(find.text('60.000 đ'), findsWidgets);

        // Tap "Tiếp tục" to navigate to Step 2
        final continueBtn = find.byKey(const Key('btn_continue'));
        expect(continueBtn, findsOneWidget);
        await tester.tap(continueBtn);
        await tester.pumpAndSettle();

        // In Step 2:
        // Cần trả NCC should be 60.000 đ (not old 30.000 đ!)
        final netPayableText = find.byKey(const Key('text_net_payable'));
        expect(netPayableText, findsOneWidget);
        expect(tester.widget<Text>(netPayableText).data, contains('60.000 đ'));

        // Tiền trả NCC input should be 60.000 đ (dynamically recalculated, not stuck at 30.000!)
        final paidInput = find.byKey(const Key('input_paid_amount'));
        expect(paidInput, findsOneWidget);
        expect(tester.widget<TextFormField>(paidInput).controller?.text, '60.000');

        // Remaining debt should be 0 đ
        final debtText = find.byKey(const Key('text_remaining_debt'));
        expect(debtText, findsOneWidget);
        expect(tester.widget<Text>(debtText).data, contains('0 đ'));
      },
    );

    testWidgets(
      'Quick action buttons [Trả đủ] and [Ghi nợ] in Step 2 adjust paidAmount instantly',
      (tester) async {
        final receipt = StockInReceipt(
          id: 'PN_DRAFT_002',
          importCode: 'PN0002',
          date: DateTime.now(),
          storeId: 'store_001',
          supplierId: 'sup_01',
          supplierName: 'Công ty TNHH Ánh Dương',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_01',
              productId: 'prod_01',
              productName: 'Bao bì 5kg',
              productCode: 'SP001',
              quantity: 2,
              unitPrice: 50000,
              originalPrice: 50000,
              discount: 0,
            ),
          ],
          totalAmount: 100000,
          paidAmount: 100000,
          discount: 0,
          status: 'draft',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: StockInPaymentConfirmationView(
              receipt: receipt,
              suppliers: const [
                Supplier(
                  id: 'sup_01',
                  name: 'Công ty TNHH Ánh Dương',
                  code: 'NCC001',
                ),
              ],
              onComplete: ({
                required supplierId,
                required discount,
                required paidAmount,
                required paymentMethod,
                required note,
              }) {},
              onSaveDraft: () {},
              onViewItems: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        final paidInput = find.byKey(const Key('input_paid_amount'));
        expect(paidInput, findsOneWidget);
        expect(tester.widget<TextFormField>(paidInput).controller?.text, '100.000');

        // Tap [Ghi nợ] button -> should set paidAmount to 0 and show 100.000 debt
        final debtZeroBtn = find.byKey(const Key('btn_pay_zero'));
        expect(debtZeroBtn, findsOneWidget);
        await tester.tap(debtZeroBtn);
        await tester.pumpAndSettle();

        expect(tester.widget<TextFormField>(paidInput).controller?.text, '0');
        final debtText = find.byKey(const Key('text_remaining_debt'));
        expect(tester.widget<Text>(debtText).data, contains('100.000 đ'));

        // Tap [Trả đủ] button -> should set paidAmount back to 100.000 and 0 debt
        final payFullBtn = find.byKey(const Key('btn_pay_in_full'));
        expect(payFullBtn, findsOneWidget);
        await tester.tap(payFullBtn);
        await tester.pumpAndSettle();

        expect(tester.widget<TextFormField>(paidInput).controller?.text, '100.000');
        expect(tester.widget<Text>(debtText).data, contains('0 đ'));
      },
    );

    testWidgets(
      'Editing discount in Step 2 dynamically updates netPayable and keeps full payment synchronized',
      (tester) async {
        final receipt = StockInReceipt(
          id: 'PN_DRAFT_003',
          importCode: 'PN0003',
          date: DateTime.now(),
          storeId: 'store_001',
          supplierId: 'sup_01',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_01',
              productId: 'prod_01',
              quantity: 1,
              unitPrice: 100000,
              originalPrice: 100000,
            ),
          ],
          totalAmount: 100000,
          paidAmount: 100000,
          discount: 0,
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: StockInPaymentConfirmationView(
              receipt: receipt,
              suppliers: const [
                Supplier(
                  id: 'sup_01',
                  name: 'Công ty TNHH Ánh Dương',
                  code: 'NCC001',
                ),
              ],
              onComplete: ({
                required supplierId,
                required discount,
                required paidAmount,
                required paymentMethod,
                required note,
              }) {},
              onSaveDraft: () {},
              onViewItems: () {},
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Enter 20000 discount
        final discountInput = find.byKey(const Key('input_receipt_discount'));
        await tester.enterText(discountInput, '20000');
        await tester.pumpAndSettle();

        // Net payable should be 80.000 đ
        final netPayableText = find.byKey(const Key('text_net_payable'));
        expect(tester.widget<Text>(netPayableText).data, contains('80.000 đ'));

        // Paid amount should automatically sync to 80.000 đ
        final paidInput = find.byKey(const Key('input_paid_amount'));
        expect(tester.widget<TextFormField>(paidInput).controller?.text, '80.000');
      },
    );

    testWidgets(
      'StockInProductEditSheet displays "Đơn giá nhập", current cost price, and allows editing',
      (tester) async {
        const product = Product(
          id: 'prod_01',
          name: 'Bao bì 5kg',
          code: 'SP001',
          price: 50000,
          costPrice: 30000,
          branchStocks: {'store_001': 10},
          category: 'Bao bì',
          unit: 'Gói',
        );

        await tester.pumpWidget(
          _buildTestApp(
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    StockInProductEditSheet.show(
                      context: context,
                      product: product,
                      branchStock: 10,
                      storeId: 'store_001',
                    );
                  },
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        // 1. Verify "Đơn giá nhập" label is present
        expect(find.text('Đơn giá nhập'), findsOneWidget);

        // 2. Verify current cost price info is displayed
        expect(find.textContaining('Vốn hiện tại: 30.000 đ'), findsOneWidget);

        // 3. Verify price input has initial cost price
        final priceInput = find.byKey(const Key('sheet_input_price'));
        expect(priceInput, findsOneWidget);
        expect(tester.widget<TextFormField>(priceInput).controller?.text, '30.000');

        // 4. Tap the net price calculation box
        final netPriceBox = find.byKey(const Key('sheet_calculated_net_price'));
        expect(netPriceBox, findsOneWidget);
        await tester.tap(netPriceBox);
        await tester.pumpAndSettle();
      },
    );
  });
}
