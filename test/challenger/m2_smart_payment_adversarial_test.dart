import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_kpi_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/core/utils/excel_helper.dart';
import 'package:stores/core/utils/invoice_print_helper.dart';
import 'package:stores/core/utils/smart_cash_helper.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/orders/pages/pos_payment_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/orders/widgets/pos_category_bar.dart';

// ============================================================================
// MOCKS & FAKES
// ============================================================================

class _MockOrderRepository implements OrderRepository {
  Order? lastCreatedOrder;
  final List<Order> storedOrders = [];

  @override
  Future<void> create(Order order) async {
    lastCreatedOrder = order;
    storedOrders.add(order);
  }

  @override
  Future<void> update(Order order) async {
    final index = storedOrders.indexWhere((o) => o.id == order.id);
    if (index != -1) storedOrders[index] = order;
  }

  @override
  Future<void> delete(String orderId) async {
    storedOrders.removeWhere((o) => o.id == orderId);
  }

  @override
  Future<Order?> fetchById(String orderId) async {
    return storedOrders.cast<Order?>().firstWhere(
          (o) => o?.id == orderId,
          orElse: () => null,
        );
  }

  @override
  Stream<List<Order>> watchAll() => Stream.value(storedOrders);

  @override
  Stream<List<Order>> watchByCustomer(String customerId) =>
      Stream.value(storedOrders.where((o) => o.customerId == customerId).toList());

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(storedOrders.where((o) {
        return o.createdAt.isAfter(start.subtract(const Duration(seconds: 1))) &&
            o.createdAt.isBefore(end.add(const Duration(seconds: 1)));
      }).toList());
}

class _MockCustomerRepository implements CustomerRepository {
  Customer? lastUpsertedCustomer;
  final Map<String, Customer> customers = {};

  _MockCustomerRepository([List<Customer> initial = const []]) {
    for (final c in initial) {
      customers[c.id] = c;
    }
  }

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());

  @override
  Future<void> upsert(Customer customer) async {
    lastUpsertedCustomer = customer;
    customers[customer.id] = customer;
  }

  @override
  Future<void> delete(String id) async {
    customers.remove(id);
  }
}

class _MockProductRepository implements ProductRepository {
  final Map<String, Product> products = {};

  _MockProductRepository([List<Product> initial = const []]) {
    for (final p in initial) {
      products[p.id] = p;
    }
  }

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());

  @override
  Future<void> upsert(Product product) async {
    products[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    products.remove(id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {}
}

class _MockInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction transaction) async {
    transactions.add(transaction);
  }

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime startDate, DateTime endDate) =>
      Stream.value(transactions);

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());
}

class _MockAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _MockAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _FakeCustomerListNotifier extends CustomerListNotifier {
  final List<Customer> _initial;
  _FakeCustomerListNotifier(this._initial);

  @override
  Future<List<Customer>> build() async => _initial;
}

// ============================================================================
// MAIN TEST SUITE
// ============================================================================

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const testConfig = StorePaymentConfig(
    storeId: 'store_001',
    storeName: 'Chi nhánh Đông Thắng',
    address: '123 Đường Đông Thắng, Cần Thơ',
    phone: '0901234567',
    bankName: 'MB Bank',
    bankId: 'mbbank',
    accountNo: '888899990000',
    accountName: 'CONG TY ABC',
    footerNote: 'Xin cảm ơn và hẹn gặp lại!',
  );

  const sampleProduct1 = Product(
    id: 'prod_mac',
    name: 'MacBook Pro M3 Max',
    code: 'MBP_M3',
    price: 1000000,
    costPrice: 800000,
    category: 'Laptop',
    branchStocks: {'store_001': 20, 'store_002': 10},
    allowSale: true,
  );

  const sampleProduct2 = Product(
    id: 'prod_ip',
    name: 'iPhone 17 Pro',
    code: 'IP17P',
    price: 340000,
    costPrice: 250000,
    category: 'Phone',
    branchStocks: {'store_001': 15, 'store_002': 5},
    allowSale: true,
  );

  const testCustomer = Customer(
    id: 'CUST_001',
    name: 'Nguyễn Văn VIP',
    phone: '0988777666',
    email: 'vip@test.com',
    address: 'Quận 1, TP.HCM',
    currentDebt: 0.0,
    purchases: [],
    branch: 'Chi nhánh Đông Thắng',
    createdAt: '2026-08-01T00:00:00Z',
    createdBy: 'admin',
    status: '1',
  );

  // --------------------------------------------------------------------------
  // GROUP 1: SmartCashHelper Boundary & Fuzzing Stress Tests
  // --------------------------------------------------------------------------
  group('1. SmartCashHelper Boundary & Adversarial Fuzzing', () {
    test('Boundary: Non-positive netPay (0, negative, floating -0.001) returns empty list', () {
      expect(SmartCashHelper.generateSmartCashSuggestions(0), isEmpty);
      expect(SmartCashHelper.generateSmartCashSuggestions(-1), isEmpty);
      expect(SmartCashHelper.generateSmartCashSuggestions(-1000000), isEmpty);
      expect(SmartCashHelper.generateSmartCashSuggestions(-0.00001), isEmpty);
    });

    test('Boundary: Minimal positive values (1đ, 999đ, 10,000đ)', () {
      final s1 = SmartCashHelper.generateSmartCashSuggestions(1);
      expect(s1.first, 1.0);
      expect(s1, containsAll([1.0, 10000.0, 20000.0, 50000.0, 100000.0]));
      expect(s1.length, lessThanOrEqualTo(5));

      final s999 = SmartCashHelper.generateSmartCashSuggestions(999);
      expect(s999.first, 999.0);
      expect(s999, containsAll([999.0, 10000.0, 20000.0, 50000.0, 100000.0]));

      final s10k = SmartCashHelper.generateSmartCashSuggestions(10000);
      expect(s10k.first, 10000.0);
      expect(s10k, containsAll([10000.0, 20000.0, 50000.0, 100000.0]));
    });

    test('Boundary: Fractional / floating point netPay (340,000.75đ)', () {
      final sFloat = SmartCashHelper.generateSmartCashSuggestions(340000.75);
      expect(sFloat.first, 340000.75);
      expect(sFloat.length, lessThanOrEqualTo(5));
      expect(sFloat, containsAll([340000.75, 350000.0, 400000.0, 500000.0]));
      for (final s in sFloat) {
        expect(s, greaterThanOrEqualTo(340000.75));
      }
      for (int i = 0; i < sFloat.length - 1; i++) {
        expect(sFloat[i], lessThan(sFloat[i + 1]));
      }
    });

    test('Boundary: Massive values (999,999,999đ and 10,000,000,000đ)', () {
      final sBillion = SmartCashHelper.generateSmartCashSuggestions(999999999);
      expect(sBillion.first, 999999999.0);
      expect(sBillion, contains(1000000000.0));
      expect(sBillion.length, lessThanOrEqualTo(5));

      final s10B = SmartCashHelper.generateSmartCashSuggestions(10000000000);
      expect(s10B.first, 10000000000.0);
      for (final s in s10B) {
        expect(s, greaterThanOrEqualTo(10000000000.0));
      }
    });

    test('Custom maxSuggestions constraints (0, 1, 3, 10)', () {
      expect(SmartCashHelper.generateSmartCashSuggestions(340000, maxSuggestions: 0), isEmpty);
      
      final s1 = SmartCashHelper.generateSmartCashSuggestions(340000, maxSuggestions: 1);
      expect(s1.length, 1);
      expect(s1.first, 340000.0);

      final s3 = SmartCashHelper.generateSmartCashSuggestions(340000, maxSuggestions: 3);
      expect(s3.length, 3);
      expect(s3, [340000.0, 350000.0, 400000.0]);

      final s10 = SmartCashHelper.generateSmartCashSuggestions(340000, maxSuggestions: 10);
      expect(s10.length, lessThanOrEqualTo(10));
      expect(s10.first, 340000.0);
    });

    test('Adversarial Fuzzing: 200 random netPay inputs strictly satisfy all mathematical invariants', () {
      final rng = Random(42);
      for (int i = 0; i < 200; i++) {
        final double amount = (rng.nextDouble() * 500000000) + 1.0;
        final int maxSugg = rng.nextInt(8) + 1; // 1 to 8

        final suggestions = SmartCashHelper.generateSmartCashSuggestions(amount, maxSuggestions: maxSugg);

        // Invariant 1: Non-empty for amount > 0
        expect(suggestions.isNotEmpty, isTrue);

        // Invariant 2: First suggestion is exact amount
        expect(suggestions.first, amount);

        // Invariant 3: Length does not exceed maxSuggestions
        expect(suggestions.length, lessThanOrEqualTo(maxSugg));

        // Invariant 4: Strictly ascending (no duplicates, sorted)
        for (int j = 0; j < suggestions.length - 1; j++) {
          expect(suggestions[j], lessThan(suggestions[j + 1]),
              reason: 'Failed monotonicity at index $j for amount $amount');
        }

        // Invariant 5: All suggestions >= amount
        for (final s in suggestions) {
          expect(s, greaterThanOrEqualTo(amount));
        }
      }
    });
  });

  // --------------------------------------------------------------------------
  // GROUP 2: Split Payment & Note Domain, Model, and Reporting Integration
  // --------------------------------------------------------------------------
  group('2. Split Payment & Note Serialization, Reporting & Helpers', () {
    final now = DateTime(2026, 8, 19, 11, 0, 0);

    test('Order entity correctly holds split payment attributes and note', () {
      final splitOrder = Order(
        id: 'HD_SPLIT_01',
        customerId: 'CUST_001',
        createdAt: now,
        items: [
          OrderItem(
            productId: 'prod_1',
            productName: 'Item 1',
            quantity: 2,
            price: 500000,
            warrantyMonths: 12,
            purchaseDate: now,
          ),
        ],
        total: 1000000,
        status: 'completed',
        amountPaid: 1000000,
        debtAmount: 0,
        paymentMethod: 'split',
        cashAmount: 400000,
        transferAmount: 600000,
        note: 'Đơn giao hỏa tốc lúc 14h',
      );

      expect(splitOrder.paymentMethod, 'split');
      expect(splitOrder.cashAmount, 400000.0);
      expect(splitOrder.transferAmount, 600000.0);
      expect(splitOrder.note, 'Đơn giao hỏa tốc lúc 14h');
      expect(splitOrder.amountPaid, 1000000.0);
      expect(splitOrder.remainingDebt, 0.0);
    });

    test('OrderModel serialization preserves exact split breakdown and special characters note', () {
      final model = OrderModel(
        id: 'HD_SERIAL_01',
        customerId: 'khach_le',
        createdAt: now,
        items: [],
        total: 2500000,
        status: 'completed',
        amountPaid: 2000000,
        debtAmount: 500000,
        paymentMethod: 'split',
        cashAmount: 1000000,
        transferAmount: 1000000,
        note: 'Ghi chú: Tiền mặt 1tr + CK VietQR 1tr. Còn nợ 500k @!#\$%^&*()',
        storeId: 'store_001',
      );

      final map = model.toMap();
      expect(map['paymentMethod'], 'split');
      expect(map['cashAmount'], 1000000.0);
      expect(map['transferAmount'], 1000000.0);
      expect(map['note'], contains('Còn nợ 500k @!#\$%^&*()'));

      final restored = OrderModel.fromMap(map);
      expect(restored.paymentMethod, 'split');
      expect(restored.cashAmount, 1000000.0);
      expect(restored.transferAmount, 1000000.0);
      expect(restored.note, model.note);
      expect(restored.debtAmount, 500000.0);
    });

    test('Backward compatibility: OrderModel deserializes legacy orders without cash/transfer/note fields', () {
      final legacyMap = {
        'id': 'HD_LEGACY_01',
        'customerId': 'khach_le',
        'createdAt': now.toIso8601String(),
        'items': [],
        'total': 1500000.0,
        'status': 'completed',
        'amountPaid': 1500000.0,
        'debtAmount': 0.0,
        'paymentMethod': 'cash',
      };

      final restored = OrderModel.fromMap(legacyMap);
      expect(restored.id, 'HD_LEGACY_01');
      expect(restored.paymentMethod, 'cash');
      expect(restored.cashAmount, isNull);
      expect(restored.transferAmount, isNull);
      expect(restored.note, isNull);
    });

    test('PaymentBreakdown provider correctly splits revenue across cash, transfer, and split orders', () async {
      final dateRange = DateTimeRange(
        start: DateTime(2026, 8, 1),
        end: DateTime(2026, 8, 31, 23, 59, 59),
      );

      final testOrders = [
        // Order 1: Cash only 500k
        Order(
          id: 'O1',
          customerId: 'khach_le',
          createdAt: now,
          items: [],
          total: 500000,
          status: 'completed',
          amountPaid: 500000,
          paymentMethod: 'cash',
        ),
        // Order 2: Transfer only 800k
        Order(
          id: 'O2',
          customerId: 'khach_le',
          createdAt: now,
          items: [],
          total: 800000,
          status: 'completed',
          amountPaid: 800000,
          paymentMethod: 'transfer',
        ),
        // Order 3: Split payment 1M (300k cash + 700k transfer)
        Order(
          id: 'O3',
          customerId: 'khach_le',
          createdAt: now,
          items: [],
          total: 1000000,
          status: 'completed',
          amountPaid: 1000000,
          paymentMethod: 'split',
          cashAmount: 300000,
          transferAmount: 700000,
        ),
        // Order 4: Partial Split with debt (Total 2M, 400k cash + 600k transfer, debt 1M)
        Order(
          id: 'O4',
          customerId: 'CUST_001',
          createdAt: now,
          items: [],
          total: 2000000,
          status: 'completed',
          amountPaid: 1000000,
          debtAmount: 1000000,
          paymentMethod: 'split',
          cashAmount: 400000,
          transferAmount: 600000,
        ),
        // Order 5: Draft order (should not count towards completed revenue)
        Order(
          id: 'O5',
          customerId: 'khach_le',
          createdAt: now,
          items: [],
          total: 9999999,
          status: 'draft',
          amountPaid: 0,
          paymentMethod: 'cash',
        ),
      ];

      final container = ProviderContainer(
        overrides: [
          overviewActiveDateRangeProvider.overrideWithValue(dateRange),
          allBranchesOrdersByDateRangeProvider.overrideWith(
            (ref, range) => Stream.value(testOrders),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Await the underlying StreamProvider
      await container.read(allBranchesOrdersByDateRangeProvider(dateRange).future);

      final breakdown = container.read(paymentBreakdownProvider).value;
      expect(breakdown, isNotNull);

      // Expected Cash: 500k (O1) + 300k (O3) + 400k (O4) = 1,200,000đ
      expect(breakdown!.cashAmount, 1200000.0);

      // Expected Transfer: 800k (O2) + 700k (O3) + 600k (O4) = 2,100,000đ
      expect(breakdown.transferAmount, 2100000.0);

      // Expected Debt: 1,000,000đ (O4)
      expect(breakdown.debtAmount, 1000000.0);

      // Total Completed Revenue: 500k + 800k + 1M + 2M = 4,300,000đ
      expect(breakdown.totalAmount, 4300000.0);
    });

    test('InvoicePrintHelper and ExcelHelper format split payment and note cleanly', () async {
      final splitOrder = Order(
        id: 'HD_SPLIT_PRINT',
        customerId: 'khach_le',
        createdAt: now,
        items: [
          OrderItem(
            productId: 'prod_1',
            productName: 'iPhone 17 Pro',
            quantity: 1,
            price: 34000000,
            warrantyMonths: 12,
            purchaseDate: now,
          )
        ],
        total: 34000000,
        status: 'completed',
        amountPaid: 34000000,
        paymentMethod: 'split',
        cashAmount: 14000000,
        transferAmount: 20000000,
        note: 'Tặng kèm ốp lưng chính hãng',
      );

      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: splitOrder,
        config: testConfig,
      );
      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(100));

      final excelBytes = await ExcelHelper.exportInvoices(
        [splitOrder],
      );
      expect(excelBytes, isNotNull);
      expect(excelBytes.length, greaterThan(100));
    });
  });

  // --------------------------------------------------------------------------
  // GROUP 3: POS Checkout UI Dual-Input Auto-Balancing & Edge Cases
  // --------------------------------------------------------------------------
  group('3. POS Payment Page Split Payment Interactive Stress Tests', () {
    // Payment controls (cash field, quick chips, split-payment modal) now live
    // in POSPaymentPage; POSCheckoutPage only builds the cart. Split payment is
    // edited through the "•••" bottom sheet (checkbox per method + amount
    // field + "Xong"), there is no auto-balance / "CK toàn bộ" shortcut any more.
    Widget buildTestApp(ProviderContainer container, {Customer? customer}) {
      return UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: const Locale('vi'),
          home: POSPaymentPage(initialCustomer: customer),
        ),
      );
    }

    ProviderContainer buildContainer({
      required _MockOrderRepository orderRepo,
      required _MockCustomerRepository custRepo,
      required String orderId,
    }) {
      return ProviderContainer(
        overrides: [
          orderRepositoryProvider.overrideWithValue(orderRepo),
          productRepositoryProvider
              .overrideWithValue(_MockProductRepository([sampleProduct1])),
          inventoryRepositoryProvider
              .overrideWithValue(_MockInventoryRepository()),
          customerRepositoryProvider.overrideWithValue(custRepo),
          storePaymentConfigProvider.overrideWithValue(testConfig),
          selectedPOSBranchProvider.overrideWith((ref) => 'store_001'),
          activeOrderIdProvider.overrideWith((ref) => orderId),
          authProvider.overrideWith((ref) => _MockAuthNotifier(const UserAccount(
                username: 'admin',
                displayName: 'Admin User',
                role: 'admin',
                storeId: 'store_001',
              ))),
          productListProvider
              .overrideWith((ref) => Stream.value([sampleProduct1])),
          customerListNotifierProvider
              .overrideWith(() => _FakeCustomerListNotifier([testCustomer])),
        ],
      );
    }

    void useBigViewport(WidgetTester tester) {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    }

    Finder sheetFields() => find.descendant(
        of: find.byType(BottomSheet), matching: find.byType(TextField));

    Finder sheetCheckbox(String title) => find.descendant(
          of: find.ancestor(
              of: find.descendant(
                  of: find.byType(BottomSheet), matching: find.text(title)),
              matching: find.byType(Row)),
          matching: find.byType(Checkbox),
        );

    testWidgets(
        'Interactive: Split modal (cash + transfer) sums into the paid amount and submits a split order',
        (tester) async {
      useBigViewport(tester);

      final mockOrderRepo = _MockOrderRepository();
      final mockCustRepo = _MockCustomerRepository([testCustomer]);
      final container = buildContainer(
          orderRepo: mockOrderRepo,
          custRepo: mockCustRepo,
          orderId: 'HD_STRESS_001');
      addTearDown(container.dispose);

      // MacBook Pro (1 x 1,000,000đ)
      container.read(cartProvider.notifier).addToCart(sampleProduct1);

      await tester.pumpWidget(buildTestApp(container));
      await tester.pumpAndSettle();

      // Open the split-payment modal via the "•••" button.
      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();
      expect(find.text('Thanh toán kết hợp'), findsOneWidget);

      // Cash is pre-checked (current method); enable transfer as well.
      await tester.tap(sheetCheckbox('Chuyển khoản').first);
      await tester.pumpAndSettle();
      expect(sheetFields(), findsNWidgets(2));

      // Cash 350,000 + Transfer 650,000
      await tester.enterText(sheetFields().at(0), '350000');
      await tester.pumpAndSettle();
      await tester.enterText(sheetFields().at(1), '650000');
      await tester.pumpAndSettle();

      // Modal summary reflects the sum of the checked methods.
      expect(
          find.descendant(
              of: find.byType(BottomSheet), matching: find.text('1.000.000')),
          findsWidgets);

      await tester.tap(find.text('Xong'));
      await tester.pumpAndSettle();

      // Page summary lists each split part.
      expect(find.text('350.000 đ'), findsWidgets);
      expect(find.text('650.000 đ'), findsWidgets);

      // Submit
      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();

      final order = mockOrderRepo.lastCreatedOrder;
      expect(order, isNotNull);
      expect(order!.paymentMethod, 'split');
      expect(order.cashAmount, 350000.0);
      expect(order.transferAmount, 650000.0);
      expect(order.amountPaid, 1000000.0);
      expect(order.debtAmount, 0.0);
    });

    testWidgets(
        'Interactive: quick "Trả đủ" chip fills cash and a cash order is fully paid',
        (tester) async {
      useBigViewport(tester);

      final mockOrderRepo = _MockOrderRepository();
      final container = buildContainer(
          orderRepo: mockOrderRepo,
          custRepo: _MockCustomerRepository([testCustomer]),
          orderId: 'HD_CHIP_001');
      addTearDown(container.dispose);
      container.read(cartProvider.notifier).addToCart(sampleProduct1);

      await tester.pumpWidget(buildTestApp(container));
      await tester.pumpAndSettle();

      final chip = find.text('1.000.000 đ (Trả đủ)');
      await tester.ensureVisible(chip);
      await tester.tap(chip);
      await tester.pumpAndSettle();

      final payField = tester.widget<TextField>(
          find.byKey(const Key('pos_payment_customer_payment_textfield')));
      expect(payField.controller?.text, '1.000.000');

      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();

      final order = mockOrderRepo.lastCreatedOrder;
      expect(order, isNotNull);
      expect(order!.cashAmount, 1000000.0);
      expect(order.transferAmount, 0.0);
      expect(order.amountPaid, 1000000.0);
      expect(order.debtAmount, 0.0);
    });

    testWidgets(
        'Adversarial: Overpayment in split mode clamps paid amount to net pay (no negative debt)',
        (tester) async {
      useBigViewport(tester);

      final mockOrderRepo = _MockOrderRepository();
      final container = buildContainer(
          orderRepo: mockOrderRepo,
          custRepo: _MockCustomerRepository([testCustomer]),
          orderId: 'HD_OVERPAY_001');
      addTearDown(container.dispose);
      container.read(cartProvider.notifier).addToCart(sampleProduct1); // 1,000,000đ

      await tester.pumpWidget(buildTestApp(container));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_horiz));
      await tester.pumpAndSettle();

      // Keep cash checked, also check transfer (left at 0) => stays "split".
      await tester.tap(sheetCheckbox('Chuyển khoản').first);
      await tester.pumpAndSettle();

      // Enter 1,500,000 into Cash (excess 500k)
      await tester.enterText(sheetFields().at(0), '1500000');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Xong'));
      await tester.pumpAndSettle();

      // Excess is surfaced as "change due" on the page.
      expect(find.textContaining('500.000'), findsWidgets);

      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();

      final order = mockOrderRepo.lastCreatedOrder;
      expect(order, isNotNull);
      expect(order!.paymentMethod, 'split');
      expect(order.amountPaid, 1000000.0); // Clamped to netPay
      expect(order.cashAmount, 1500000.0);
      expect(order.transferAmount, 0.0);
      expect(order.debtAmount, 0.0);
    });

    testWidgets(
        'Adversarial: Walk-in retail customer debt is strictly blocked in underpayment; named customer allows debt',
        (tester) async {
      useBigViewport(tester);

      final mockOrderRepo = _MockOrderRepository();
      final mockCustRepo = _MockCustomerRepository([testCustomer]);
      final container = buildContainer(
          orderRepo: mockOrderRepo,
          custRepo: mockCustRepo,
          orderId: 'HD_DEBT_001');
      addTearDown(container.dispose);
      container.read(cartProvider.notifier).addToCart(sampleProduct1); // 1,000,000đ

      // Case 1: Walk-in customer (no initialCustomer) -> underpayment BLOCKED
      await tester.pumpWidget(buildTestApp(container));
      await tester.pumpAndSettle();

      final paymentFieldFinder =
          find.byKey(const Key('pos_payment_customer_payment_textfield'));
      await tester.enterText(paymentFieldFinder, '400000'); // Debt: 600,000đ
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();

      expect(mockOrderRepo.lastCreatedOrder, isNull); // Blocked!
      expect(
          find.text(
              'Khách lẻ không thể ghi nợ. Vui lòng chọn hoặc tạo khách hàng!'),
          findsOneWidget);

      // Case 2: Registered customer -> debt allowed
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpWidget(buildTestApp(container, customer: testCustomer));
      await tester.pumpAndSettle();

      await tester.enterText(
          find.byKey(const Key('pos_payment_customer_payment_textfield')),
          '400000');
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'Thanh toán'));
      await tester.pumpAndSettle();

      final order = mockOrderRepo.lastCreatedOrder;
      expect(order, isNotNull);
      expect(order!.customerId, 'CUST_001');
      expect(order.amountPaid, 400000.0);
      expect(order.debtAmount, 600000.0);

      // Customer debt updated in repository
      final updatedCust = mockCustRepo.lastUpsertedCustomer;
      expect(updatedCust, isNotNull);
      expect(updatedCust!.displayCurrentDebt, 600000.0);
    });
  });

  // --------------------------------------------------------------------------
  // GROUP 4: POS Category Bar & Search Adversarial Filtering Tests
  // --------------------------------------------------------------------------
  group('4. POS Category Bar & Search Adversarial Filtering', () {
    final testCategories = [
      const Category(id: 'cat_laptop', name: 'Laptop'),
      const Category(id: 'cat_phone', name: 'Phone'),
      const Category(id: 'cat_acc', name: 'Phụ kiện'),
    ];

    final testProducts = [
      sampleProduct1, // Laptop (Stock 20/10)
      sampleProduct2, // Phone (Stock 15/5)
      const Product(
        id: 'prod_oos',
        name: 'Chuột Magic Mouse',
        code: 'MM01',
        price: 2000000,
        costPrice: 1500000,
        category: 'Phụ kiện',
        branchStocks: {'store_001': 0, 'store_002': 5},
        allowSale: true,
        minStock: 2,
      ),
      const Product(
        id: 'prod_hidden',
        name: 'Sản phẩm ngưng bán',
        code: 'HIDDEN',
        price: 100000,
        costPrice: 50000,
        category: 'Laptop',
        branchStocks: {'store_001': 100},
        allowSale: false, // NOT allowed for sale
      ),
    ];

    testWidgets('PosCategoryBar dynamically counts only allowed-for-sale products per category', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
            productListProvider.overrideWith((ref) => Stream.value(testProducts)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PosCategoryBar(
                selectedCategoryId: 'all',
                onCategorySelected: (_, __) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Total allowed-for-sale products: 3 (sampleProduct1, sampleProduct2, prod_oos)
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // Total badge
      expect(find.text('Laptop'), findsOneWidget);
      expect(find.text('Phone'), findsOneWidget);
      expect(find.text('Phụ kiện'), findsOneWidget);
    });

    testWidgets('POSPage combined search query + category filtering + branch stock badge', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(testCategories)),
            productListProvider.overrideWith((ref) => Stream.value(testProducts)),
            currentStoreNameProvider.overrideWith((ref) => 'Chi nhánh Đông Thắng'),
            selectedPOSBranchProvider.overrideWith((ref) => 'store_001'),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: POSPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Out of stock product shows 'Hết hàng' badge and 'ĐT: 0 | TB: 5'
      expect(find.text('Chuột Magic Mouse'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);
      expect(find.textContaining('ĐT: 0 | TB: 5'), findsOneWidget);

      // Filter by Laptop category
      await tester.tap(find.text('Laptop'));
      await tester.pumpAndSettle();

      expect(find.text('MacBook Pro M3 Max'), findsOneWidget);
      expect(find.text('iPhone 17 Pro'), findsNothing);
      expect(find.text('Chuột Magic Mouse'), findsNothing);

      // Search non-existent name under Laptop category -> Empty state
      await tester.enterText(find.byType(TextField).first, 'Galaxy');
      await tester.pumpAndSettle();

      expect(find.text('MacBook Pro M3 Max'), findsNothing);
      expect(find.text('Không tìm thấy sản phẩm phù hợp'), findsOneWidget);
    });
  });
}
