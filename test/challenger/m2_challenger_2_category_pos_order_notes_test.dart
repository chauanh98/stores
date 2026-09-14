import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/utils/invoice_print_helper.dart';
import 'package:stores/data/models/order_item_model.dart';
import 'package:stores/data/models/order_model.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/orders/widgets/pos_category_bar.dart';

class _MockOrderRepository implements OrderRepository {
  final List<Order> orders = [];

  _MockOrderRepository([List<Order> initial = const []]) {
    orders.addAll(initial);
  }

  @override
  Future<void> create(Order order) async => orders.add(order);

  @override
  Future<void> update(Order order) async {
    final idx = orders.indexWhere((o) => o.id == order.id);
    if (idx != -1) orders[idx] = order;
  }

  @override
  Future<void> delete(String orderId) async => orders.removeWhere((o) => o.id == orderId);

  @override
  Future<Order?> fetchById(String orderId) async =>
      orders.cast<Order?>().firstWhere((o) => o?.id == orderId, orElse: () => null);

  @override
  Stream<List<Order>> watchAll() => Stream.value(orders);

  @override
  Stream<List<Order>> watchByCustomer(String customerId) =>
      Stream.value(orders.where((o) => o.customerId == customerId).toList());

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(orders);
}

class _FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _FakeCustomerListNotifier extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  final List<Customer> _initialCustomers;
  _FakeCustomerListNotifier(this._initialCustomers);

  @override
  Future<List<Customer>> build() async => _initialCustomers;

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ==========================================================================
  // SUITE 1: PosCategoryBar & Dynamic Product Count Badge Adversarial Tests
  // ==========================================================================
  group('PosCategoryBar & Dynamic Count Badge Stress Tests', () {
    final categories = [
      const Category(id: 'cat_phone', name: 'Điện thoại'),
      const Category(id: 'cat_laptop', name: 'Laptop Gaming'),
      const Category(id: 'cat_acc', name: 'Phụ kiện'),
      const Category(id: 'cat_empty', name: 'Gia dụng'),
    ];

    final products = [
      // 1. Phone active
      const Product(
        id: 'p1',
        name: 'iPhone 17 Pro Max',
        code: 'IP17PM',
        price: 35000000,
        costPrice: 30000000,
        category: 'Điện thoại',
        branchStocks: {'store_001': 10, 'store_002': 5},
        allowSale: true,
      ),
      // 2. Phone active with hierarchical naming
      const Product(
        id: 'p2',
        name: 'Galaxy S25 Ultra',
        code: 'S25U',
        price: 28000000,
        costPrice: 24000000,
        category: 'Điện thoại >> Android',
        branchStocks: {'store_001': 4},
        allowSale: true,
      ),
      // 3. Phone INACTIVE / stopped selling (must NOT be counted)
      const Product(
        id: 'p3',
        name: 'iPhone 11 Cũ (Ngừng bán)',
        code: 'IP11OLD',
        price: 5000000,
        costPrice: 4000000,
        category: 'Điện thoại',
        branchStocks: {'store_001': 10},
        allowSale: false, // Discontinued
      ),
      // 4. Laptop active with sub-category match
      const Product(
        id: 'p4',
        name: 'ASUS ROG Zephyrus G16',
        code: 'ASUSG16',
        price: 55000000,
        costPrice: 48000000,
        category: 'Laptop', // Category name is 'Laptop Gaming'
        branchStocks: {'store_001': 2},
        allowSale: true,
      ),
      // 5. Accessory active (case insensitive, accented match)
      const Product(
        id: 'p5',
        name: 'Cáp sạc Type-C 100W',
        code: 'CABLE100',
        price: 250000,
        costPrice: 150000,
        category: 'phụ kiện',
        branchStocks: {'store_001': 50},
        allowSale: true,
      ),
    ];

    testWidgets('PosCategoryBar computes accurate counts excluding allowSale=false', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      String? selectedCatId;
      String? selectedCatName;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(categories)),
            productListProvider.overrideWith((ref) => Stream.value(products)),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: PosCategoryBar(
                selectedCategoryId: 'all',
                onCategorySelected: (id, name) {
                  selectedCatId = id;
                  selectedCatName = name;
                },
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Check all chips rendered
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('Điện thoại'), findsOneWidget);
      expect(find.text('Laptop Gaming'), findsOneWidget);
      expect(find.text('Phụ kiện'), findsOneWidget);
      expect(find.text('Gia dụng'), findsOneWidget);

      // Verify product count badges:
      // 'Tất cả' should count 4 (p1, p2, p4, p5) and exclude p3 (allowSale=false)
      expect(find.text('4'), findsOneWidget);
      // 'Điện thoại' should count 2 (p1, p2) and exclude p3
      expect(find.text('2'), findsOneWidget);
      // 'Laptop Gaming' should count 1 (p4)
      // 'Phụ kiện' should count 1 (p5)
      expect(find.text('1'), findsNWidgets(2));
      // 'Gia dụng' has 0 products
      expect(find.text('0'), findsOneWidget);

      // Tap on 'Phụ kiện'
      await tester.tap(find.text('Phụ kiện'));
      await tester.pumpAndSettle();

      expect(selectedCatId, 'cat_acc');
      expect(selectedCatName, 'Phụ kiện');
    });

    testWidgets('PosCategoryBar gracefully handles empty categories and product list', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            categoryListProvider.overrideWith((ref) => Stream.value(<Category>[])),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
          ],
          child: const MaterialApp(
            home: Scaffold(
              body: PosCategoryBar(selectedCategoryId: 'all'),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Should render at least 'Tất cả' with count 0
      expect(find.text('Tất cả'), findsOneWidget);
      expect(find.text('0'), findsOneWidget);
    });
  });

  // ==========================================================================
  // SUITE 2: POSPage Combined Filtering & Product Card Stock UI Stress Tests
  // ==========================================================================
  group('POSPage Combined Filtering & Product Card UI Stress Tests', () {
    final categories = [
      const Category(id: 'cat_phone', name: 'Điện thoại'),
      const Category(id: 'cat_laptop', name: 'Laptop'),
      const Category(id: 'cat_audio', name: 'Âm thanh'),
    ];

    const comboComponent1 = Product(
      id: 'comp_1',
      name: 'Chuột Gaming RGB',
      code: 'MOUSE01',
      price: 500000,
      costPrice: 300000,
      category: 'Phụ kiện',
      branchStocks: {'store_001': 10, 'store_002': 0},
      allowSale: true,
      minStock: 2,
    );

    const comboComponent2 = Product(
      id: 'comp_2',
      name: 'Bàn phím cơ TKL',
      code: 'KB01',
      price: 1200000,
      costPrice: 800000,
      category: 'Phụ kiện',
      branchStocks: {'store_001': 3, 'store_002': 5},
      allowSale: true,
      minStock: 2,
    );

    final products = [
      const Product(
        id: 'p101',
        name: 'iPhone 17 Pro Max 256GB',
        code: 'IP17PM-256',
        brand: 'Apple',
        price: 36000000,
        costPrice: 31000000,
        category: 'Điện thoại',
        branchStocks: {'store_001': 12, 'store_002': 8, 'store_003': 3},
        allowSale: true,
        minStock: 5,
      ),
      const Product(
        id: 'p102',
        name: 'Samsung Galaxy Z Fold 7',
        code: 'ZFOLD7',
        brand: 'Samsung',
        price: 42000000,
        costPrice: 36000000,
        category: 'Điện thoại',
        branchStocks: {'store_001': 2, 'store_002': 0}, // Low stock in store_001 (2 <= minStock 3)
        allowSale: true,
        minStock: 3,
      ),
      const Product(
        id: 'p103',
        name: 'MacBook Air M3',
        code: 'MBA-M3',
        brand: 'Apple',
        price: 27000000,
        costPrice: 23000000,
        category: 'Laptop',
        branchStocks: {'store_001': 0, 'store_002': 4}, // Out of stock in store_001
        allowSale: true,
        minStock: 2,
      ),
      const Product(
        id: 'p104',
        name: 'Tai nghe Sony WH-1000XM6',
        code: 'SONY-XM6',
        brand: 'Sony',
        price: 8500000,
        costPrice: 6500000,
        category: 'Âm thanh',
        branchStocks: {}, // No branch stocks specified
        allowSale: true,
        minStock: 2,
      ),
      comboComponent1,
      comboComponent2,
      const Product(
        id: 'p105_combo',
        name: 'Combo Gaming Gear Pro',
        code: 'COMBO-GG',
        brand: 'Custom',
        price: 1500000,
        costPrice: 1100000,
        category: 'Laptop',
        branchStocks: {'store_001': 0},
        allowSale: true,
        isCombo: true,
        comboComponents: [
          ComboComponent(productId: 'comp_1', productCode: 'MOUSE01', productName: 'Chuột Gaming RGB', quantity: 1),
          ComboComponent(productId: 'comp_2', productCode: 'KB01', productName: 'Bàn phím cơ TKL', quantity: 1),
        ],
      ),
    ];

    Widget createPOSWidget({String branch = 'store_001'}) {
      return ProviderScope(
        overrides: [
          categoryListProvider.overrideWith((ref) => Stream.value(categories)),
          productListProvider.overrideWith((ref) => Stream.value(products)),
          currentStoreNameProvider.overrideWith((ref) => 'Đông Thắng Store (ĐT)'),
          selectedPOSBranchProvider.overrideWith((ref) => branch),
          authProvider.overrideWith((ref) =>
              _FakeAuthNotifier(const UserAccount(username: 'cashier', displayName: 'Thu ngân 1', role: 'staff', storeId: 'store_001'))),
        ],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: POSPage(),
        ),
      );
    }

    testWidgets('POSPage renders multi-branch stock tags (ĐT, TB, CN3) and stock badges', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createPOSWidget(branch: 'store_001'));
      await tester.pumpAndSettle();

      // Multi-branch stock labels
      expect(find.textContaining('ĐT: 12 | TB: 8 | CN3: 3'), findsOneWidget);
      expect(find.textContaining('ĐT: 2 | TB: 0'), findsOneWidget);
      expect(find.textContaining('ĐT: 0 | TB: 4'), findsOneWidget);

      // Stock status badges
      expect(find.text('Còn hàng'), findsWidgets);
      expect(find.text('Sắp hết'), findsWidgets);
      expect(find.text('Hết hàng'), findsWidgets);

      // Combo item preview
      expect(find.text('COMBO'), findsOneWidget);
      expect(find.textContaining('Gồm: 1x Chuột Gaming RGB, 1x Bàn phím cơ TKL'), findsOneWidget);
    });

    testWidgets('POSPage combined Category + Search keyword filtering with clearance', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createPOSWidget());
      await tester.pumpAndSettle();

      // 1. Select 'Điện thoại'
      await tester.tap(find.text('Điện thoại'));
      await tester.pumpAndSettle();

      // Should show iPhone 17 and Samsung Z Fold, but not MacBook or Sony
      expect(find.text('iPhone 17 Pro Max 256GB'), findsOneWidget);
      expect(find.text('Samsung Galaxy Z Fold 7'), findsOneWidget);
      expect(find.text('MacBook Air M3'), findsNothing);
      expect(find.text('Tai nghe Sony WH-1000XM6'), findsNothing);

      // 2. Add search query 'Apple' (matches brand of iPhone)
      final searchField = find.byType(TextField).first;
      await tester.enterText(searchField, 'Apple');
      await tester.pumpAndSettle();

      expect(find.text('iPhone 17 Pro Max 256GB'), findsOneWidget);
      expect(find.text('Samsung Galaxy Z Fold 7'), findsNothing);

      // 3. Search query matching code 'ZFOLD7' while 'Điện thoại' is selected
      await tester.enterText(searchField, 'ZFOLD7');
      await tester.pumpAndSettle();

      expect(find.text('Samsung Galaxy Z Fold 7'), findsOneWidget);
      expect(find.text('iPhone 17 Pro Max 256GB'), findsNothing);

      // 4. Search query with non-matching keyword in 'Điện thoại'
      await tester.enterText(searchField, 'Sony');
      await tester.pumpAndSettle();

      expect(find.textContaining('Không tìm thấy sản phẩm'), findsOneWidget);

      // 5. Clear search query via clear icon
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Should revert to all 'Điện thoại' items
      expect(find.text('iPhone 17 Pro Max 256GB'), findsOneWidget);
      expect(find.text('Samsung Galaxy Z Fold 7'), findsOneWidget);
    });

    testWidgets('Quick Cart +/- controls enforce stock bounds and show alerts', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(createPOSWidget(branch: 'store_001'));
      await tester.pumpAndSettle();

      // 1. Try to add MacBook Air M3 (stock = 0 in store_001)
      final macbookAddBtn = find.descendant(
        of: find.ancestor(of: find.text('MacBook Air M3'), matching: find.byType(Container)),
        matching: find.byIcon(Icons.add),
      ).first;

      await tester.tap(macbookAddBtn);
      await tester.pumpAndSettle();

      // Should show out of stock alert snackbar
      expect(find.textContaining('Sản phẩm đã hết hàng'), findsOneWidget);
      ScaffoldMessenger.of(tester.element(find.byType(POSPage))).clearSnackBars();
      await tester.pumpAndSettle();

      // 2. Add Samsung Z Fold 7 (stock = 2 in store_001)
      final zfoldAddBtn = find.descendant(
        of: find.ancestor(of: find.text('Samsung Galaxy Z Fold 7'), matching: find.byType(Container)),
        matching: find.byIcon(Icons.add),
      ).first;

      // Tap 1: Add first item
      await tester.tap(zfoldAddBtn);
      await tester.pumpAndSettle();

      expect(find.text('1'), findsWidgets);

      final plusBtn = find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.add && w.size == 14);
      final minusBtn = find.byWidgetPredicate((w) => w is Icon && w.icon == Icons.remove && w.size == 14);

      // Tap 2: Increase to 2 items (matches stock limit 2)
      await tester.tap(plusBtn);
      await tester.pumpAndSettle();

      expect(find.text('2'), findsWidgets);

      // Tap 3: Exceed stock limit (attempts 3rd item)
      await tester.tap(plusBtn);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Should show stock limit snackbar
      expect(find.textContaining('Không thể vượt quá số lượng tồn kho (2)!'), findsOneWidget);

      // Tap '-': Decrement to 1
      await tester.tap(minusBtn);
      await tester.pumpAndSettle();

      // Tap '-' again: Remove completely
      await tester.tap(minusBtn);
      await tester.pumpAndSettle();

      // Bottom cart bar should be gone
      expect(find.text('Thanh toán'), findsNothing);
    });
  });

  // ==========================================================================
  // SUITE 3: Order Note & Split Payment Persistence & Serialization
  // ==========================================================================
  group('Order Note & Split Payment Persistence & Serialization Stress Tests', () {
    test('Order & OrderModel round-trip preserves multiline notes, split amounts, and unicode', () {
      final now = DateTime(2026, 8, 19, 10, 30);
      const multilineNote = '''
Khách yêu cầu:
1. Giao hỏa tốc trước 15:00
2. Xuất VAT CTY TNHH ABC: MST 0312345678
3. Kèm quà tặng combo tai nghe 🎧
4. Special chars: <tag> "quotes" & 'ampersand'
''';

      final originalOrder = Order(
        id: 'HD_TEST_NOTE_001',
        customerId: 'CUST_001',
        createdAt: now,
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'iPhone 17 Pro',
            quantity: 1,
            price: 30000000,
            warrantyMonths: 12,
            purchaseDate: now,
          )
        ],
        total: 30000000,
        status: 'completed',
        amountPaid: 30000000,
        debtAmount: 0.0,
        paymentMethod: 'split',
        createdBy: 'admin',
        createdByName: 'Quản trị viên',
        storeId: 'store_001',
        cashAmount: 10000000,
        transferAmount: 20000000,
        note: multilineNote,
      );

      // Convert Order -> OrderModel -> Map -> OrderModel -> Order
      final model = OrderModel(
        id: originalOrder.id,
        customerId: originalOrder.customerId,
        createdAt: originalOrder.createdAt,
        items: originalOrder.items
            .map((i) => OrderItemModel(
                  productId: i.productId,
                  productName: i.productName,
                  quantity: i.quantity,
                  price: i.price,
                  warrantyMonths: i.warrantyMonths,
                  purchaseDate: i.purchaseDate,
                ))
            .toList(),
        total: originalOrder.total,
        status: originalOrder.status,
        amountPaid: originalOrder.amountPaid,
        debtAmount: originalOrder.debtAmount,
        paymentMethod: originalOrder.paymentMethod,
        createdBy: originalOrder.createdBy,
        createdByName: originalOrder.createdByName,
        storeId: originalOrder.storeId,
        cashAmount: originalOrder.cashAmount,
        transferAmount: originalOrder.transferAmount,
        note: originalOrder.note,
      );

      final map = model.toMap();
      expect(map['note'], multilineNote);
      expect(map['cashAmount'], 10000000.0);
      expect(map['transferAmount'], 20000000.0);
      expect(map['paymentMethod'], 'split');

      final deserializedModel = OrderModel.fromMap(map);
      expect(deserializedModel.note, multilineNote);
      expect(deserializedModel.cashAmount, 10000000.0);
      expect(deserializedModel.transferAmount, 20000000.0);
      expect(deserializedModel.paymentMethod, 'split');
    });

    test('OrderModel deserialization defaults gracefully when note and split fields are null', () {
      final legacyMap = {
        'id': 'HD_LEGACY_001',
        'customerId': 'CUST_LEGACY',
        'createdAt': '2026-08-19T00:00:00.000',
        'total': 500000.0,
        'items': [],
        'status': 'completed',
        'paymentMethod': 'cash',
      };

      final model = OrderModel.fromMap(legacyMap);
      expect(model.note, isNull);
      expect(model.cashAmount, isNull);
      expect(model.transferAmount, isNull);
      expect(model.amountPaid, 500000.0);
    });

    test('Order copyWith preserves or updates note and split payment fields correctly', () {
      final now = DateTime(2026, 8, 19);
      final order = Order(
        id: 'HD001',
        customerId: 'CUST1',
        createdAt: now,
        items: const [],
        total: 1000000,
        paymentMethod: 'cash',
        note: 'Ghi chú ban đầu',
      );

      final updated = order.copyWith(
        paymentMethod: 'split',
        cashAmount: 400000,
        transferAmount: 600000,
        note: 'Ghi chú đã sửa',
      );

      expect(updated.paymentMethod, 'split');
      expect(updated.cashAmount, 400000.0);
      expect(updated.transferAmount, 600000.0);
      expect(updated.note, 'Ghi chú đã sửa');
      expect(updated.id, 'HD001');
    });
  });

  // ==========================================================================
  // SUITE 4: InvoicesPage Details & InvoicePrintHelper PDF Rendering
  // ==========================================================================
  group('InvoicesPage Details & InvoicePrintHelper PDF Rendering Tests', () {
    final now = DateTime.now();

    final orderWithNoteAndSplit = Order(
      id: 'HD_NOTE_SPLIT_999',
      customerId: 'cust_001',
      createdAt: now.subtract(const Duration(minutes: 5)),
      items: [
        OrderItem(
          productId: 'P99',
          productName: 'Màn hình Dell UltraSharp 27',
          quantity: 1,
          price: 12000000,
          warrantyMonths: 36,
          purchaseDate: now,
        )
      ],
      total: 12000000,
      amountPaid: 12000000,
      debtAmount: 0.0,
      paymentMethod: 'split',
      cashAmount: 5000000,
      transferAmount: 7000000,
      note: 'Khách thanh toán 5tr tiền mặt và 7tr quét mã VietQR',
      createdBy: 'admin',
      createdByName: 'Nguyễn Văn Quản Trị',
    );

    final orderWithoutNote = Order(
      id: 'HD_NO_NOTE_111',
      customerId: 'cust_001',
      createdAt: now.subtract(const Duration(minutes: 10)),
      items: [
        OrderItem(
          productId: 'P1',
          productName: 'Chuột Logitech MX Master 3S',
          quantity: 1,
          price: 2500000,
          warrantyMonths: 12,
          purchaseDate: now,
        )
      ],
      total: 2500000,
      amountPaid: 2500000,
      paymentMethod: 'cash',
    );

    const adminUser = UserAccount(
      username: 'admin',
      displayName: 'Quản trị viên',
      role: 'admin',
      storeId: 'store_001',
    );

    const customer1 = Customer(
      id: 'cust_001',
      name: 'Nguyễn Văn A',
      phone: '0901234567',
      email: '',
      address: '',
      purchases: [],
    );

    testWidgets('InvoicesPage details modal displays note and split payment method', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeOrderRepo = _MockOrderRepository([orderWithNoteAndSplit, orderWithoutNote]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            orderRepositoryProvider.overrideWithValue(fakeOrderRepo),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            accountsListProvider.overrideWith((ref) => Stream.value([adminUser])),
            allBranchesOrdersByDateRangeProvider.overrideWith(
                (ref, range) => Stream.value([orderWithNoteAndSplit, orderWithoutNote])),
            customerListNotifierProvider.overrideWith(() => _FakeCustomerListNotifier([customer1])),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            currentStoreNameProvider.overrideWith((ref) => 'Đông Thắng Store'),
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: InvoicesPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Tap on invoice HD_NOTE_SPLIT_999 to open detail bottom sheet
      expect(find.text('Mã đơn: HD_NOTE_SPLIT_999'), findsOneWidget);
      await tester.tap(find.text('Mã đơn: HD_NOTE_SPLIT_999'));
      await tester.pumpAndSettle();

      // Verify payment method row displays 'Kết hợp (TM + CK)'
      expect(find.text('Kết hợp (TM + CK)'), findsOneWidget);

      // Verify 'Ghi chú' row is displayed with exact content
      expect(find.text('Ghi chú'), findsOneWidget);
      expect(find.text('Khách thanh toán 5tr tiền mặt và 7tr quét mã VietQR'), findsOneWidget);
    });

    test('InvoicePrintHelper generates valid PDF with note and split payment breakdown', () async {
      const config = StorePaymentConfig(
        storeId: 'store_001',
        storeName: 'Đông Thắng Store',
        address: '123 Đông Thắng',
        phone: '0901234567',
        bankName: 'Vietcombank',
        bankId: 'vietcombank',
        accountNo: '123456789',
        accountName: 'NGUYEN VAN A',
        footerNote: 'Cảm ơn quý khách và hẹn gặp lại!',
      );

      // 1. Generate PDF with note & split payment
      final pdfBytes = await InvoicePrintHelper.buildPdf(
        order: orderWithNoteAndSplit,
        config: config,
      );

      expect(pdfBytes, isNotNull);
      expect(pdfBytes.length, greaterThan(0));

      // 2. Generate PDF without note
      final pdfBytesNoNote = await InvoicePrintHelper.buildPdf(
        order: orderWithoutNote,
        config: config,
      );

      expect(pdfBytesNoNote, isNotNull);
      expect(pdfBytesNoNote.length, greaterThan(0));
    });
  });
}
