import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';

class _FakeOrderRepository implements OrderRepository {
  final List<Order> createdOrders = [];

  @override
  Future<void> create(Order order) async {
    createdOrders.add(order);
  }

  @override
  Future<void> update(Order order) async {}

  @override
  Future<void> delete(String orderId) async {}

  @override
  Future<Order?> fetchById(String orderId) async => null;

  @override
  Stream<List<Order>> watchAll() => Stream.value(createdOrders);

  @override
  Stream<List<Order>> watchByCustomer(String customerId) => Stream.value([]);

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) =>
      Stream.value(createdOrders);
}

class _FakeProductRepository implements ProductRepository {
  final Map<String, Product> products;
  _FakeProductRepository(this.products);

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<void> upsert(Product product) async {
    products[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> updateStock(String id, int newStock) async {}

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());
}

class _FakeCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers;
  _FakeCustomerRepository(this.customers);

  @override
  Future<Customer?> fetchById(String id) async => customers[id];

  @override
  Future<void> upsert(Customer customer) async {
    customers[customer.id] = customer;
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());
}

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

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  _FakeCustomerListNotifier(this._initialCustomers);

  final List<Customer> _initialCustomers;

  @override
  Future<List<Customer>> build() async {
    return _initialCustomers;
  }

  @override
  Future<void> refresh() async {
    state = AsyncValue.data(_initialCustomers);
  }
}

void main() {
  const testUser = UserAccount(
    username: 'admin_tb',
    displayName: 'Thới Bình Admin',
    role: 'admin',
    storeId: 'store_002',
  );

  const testProduct = Product(
    id: 'PROD_TB_01',
    code: 'TB01',
    name: 'Bồn nước 1000L Thới Bình',
    price: 3000000.0,
    costPrice: 2000000.0,
    branchStocks: {'store_002': 10},
    category: 'Bồn nước',
  );

  const testCustomer = Customer(
    id: 'CUST_TB_01',
    name: 'Nguyễn Văn Thới',
    phone: '0912345678',
    email: 'thoi@example.com',
    address: 'Thới Bình, Cà Mau',
    purchases: [],
  );

  late _FakeOrderRepository fakeOrderRepo;
  late _FakeProductRepository fakeProductRepo;
  late _FakeCustomerRepository fakeCustomerRepo;

  setUp(() {
    fakeOrderRepo = _FakeOrderRepository();
    fakeProductRepo = _FakeProductRepository({testProduct.id: testProduct});
    fakeCustomerRepo = _FakeCustomerRepository({testCustomer.id: testCustomer});
  });

  testWidgets(
      'POS Checkout with discount creates Order with total=gross, discount, netPayable, remainingDebt, and storeId',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
        orderRepositoryProvider.overrideWithValue(fakeOrderRepo),
        productRepositoryProvider.overrideWithValue(fakeProductRepo),
        customerRepositoryProvider.overrideWithValue(fakeCustomerRepo),
        allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) => Stream.value([])),
        selectedPOSBranchProvider.overrideWith((ref) => 'store_002'),
        storePaymentConfigProvider.overrideWith((ref) => const StorePaymentConfig(
              storeId: 'store_002',
              bankName: 'Vietcombank',
              accountNo: '123456789',
              accountName: 'KHANH DANG STORE',
            )),
      ],
    );
    addTearDown(container.dispose);

    // Pre-populate Cart with 2 items (gross = 6,000,000 đ)
    container.read(cartProvider.notifier).addToCart(testProduct, quantity: 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: POSCheckoutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Verify initial gross total in UI: 6,000,000 đ
    expect(find.text('6.000.000 đ'), findsWidgets);

    // Enter Discount of 500,000 đ
    final discountField = find.byKey(const Key('pos_discount_textfield'));
    await tester.enterText(discountField, '500000');
    await tester.pumpAndSettle();

    // Now Net Pay is 5,500,000 đ
    expect(find.text('5.500.000 đ'), findsWidgets);

    // Click checkout button
    final checkoutButton = find.widgetWithText(ElevatedButton, 'Thanh toán');
    expect(checkoutButton, findsOneWidget);
    await tester.tap(checkoutButton);
    await tester.pumpAndSettle();

    // Verify Order creation contract
    expect(fakeOrderRepo.createdOrders.length, 1);
    final order = fakeOrderRepo.createdOrders.first;

    // 1. Gross total (Tổng tiền hàng) MUST be 6,000,000 đ
    expect(order.total, equals(6000000.0));

    // 2. Discount (Giảm giá hóa đơn) MUST be 500,000 đ
    expect(order.discount, equals(500000.0));

    // 3. Net payable (Khách cần trả) MUST be 5,500,000 đ
    expect(order.netPayable, equals(5500000.0));

    // 4. Default cash payment paid netPayable in full (5,500,000 đ)
    expect(order.amountPaid, equals(5500000.0));

    // 5. Remaining debt MUST be 0.0 đ
    expect(order.remainingDebt, equals(0.0));
    expect(order.hasDebt, isFalse);

    // 6. storeId MUST be store_002 (Chi nhánh Thới Bình)
    expect(order.storeId, equals('store_002'));
  });

  testWidgets(
      'POS Checkout with named customer and partial payment calculates debt after discount accurately',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    final container = ProviderContainer(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(testUser)),
        orderRepositoryProvider.overrideWithValue(fakeOrderRepo),
        productRepositoryProvider.overrideWithValue(fakeProductRepo),
        customerRepositoryProvider.overrideWithValue(fakeCustomerRepo),
        customerListNotifierProvider.overrideWith(() => _FakeCustomerListNotifier([testCustomer])),
        allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) => Stream.value([])),
        selectedPOSBranchProvider.overrideWith((ref) => 'store_002'),
        storePaymentConfigProvider.overrideWith((ref) => const StorePaymentConfig(
              storeId: 'store_002',
              bankName: 'Vietcombank',
              accountNo: '123456789',
              accountName: 'KHANH DANG STORE',
            )),
      ],
    );
    addTearDown(container.dispose);

    // Pre-populate Cart with 2 items (gross = 6,000,000 đ)
    container.read(cartProvider.notifier).addToCart(testProduct, quantity: 2);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          locale: Locale('vi'),
          home: POSCheckoutPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Select Customer CUST_TB_01
    await tester.tap(find.text('Thay đổi'));
    await tester.pumpAndSettle();

    // Tap the customer in bottom sheet
    await tester.tap(find.text('Nguyễn Văn Thới'));
    await tester.pumpAndSettle();

    // Enter Discount of 1,000,000 đ -> Net Pay = 5,000,000 đ
    final discountField = find.byKey(const Key('pos_discount_textfield'));
    await tester.enterText(discountField, '1000000');
    await tester.pumpAndSettle();

    // Customer pays partial amount 3,000,000 đ
    final paymentField = find.byKey(const Key('pos_customer_payment_textfield'));
    await tester.enterText(paymentField, '3000000');
    await tester.pumpAndSettle();

    // Click checkout button
    final checkoutButton = find.widgetWithText(ElevatedButton, 'Thanh toán');
    await tester.tap(checkoutButton);
    await tester.pumpAndSettle();

    // Verify Order creation contract
    expect(fakeOrderRepo.createdOrders.length, 1);
    final order = fakeOrderRepo.createdOrders.first;

    // 1. Gross total: 6,000,000 đ
    expect(order.total, equals(6000000.0));

    // 2. Discount: 1,000,000 đ
    expect(order.discount, equals(1000000.0));

    // 3. Net payable: 5,000,000 đ
    expect(order.netPayable, equals(5000000.0));

    // 4. Amount paid: 3,000,000 đ
    expect(order.amountPaid, equals(3000000.0));

    // 5. Remaining debt: 2,000,000 đ
    expect(order.debtAmount, equals(2000000.0));
    expect(order.remainingDebt, equals(2000000.0));
    expect(order.hasDebt, isTrue);

    // 6. Customer link and storeId
    expect(order.customerId, equals('CUST_TB_01'));
    expect(order.customerName, equals('Nguyễn Văn Thới'));
    expect(order.storeId, equals('store_002'));

    // 7. Customer financial totals: totalSales=6,000,000 (gross), netSales=5,000,000 (net), currentDebt=2,000,000
    final updatedCustomer = fakeCustomerRepo.customers['CUST_TB_01'];
    expect(updatedCustomer?.totalSales, equals(6000000.0));
    expect(updatedCustomer?.netSales, equals(5000000.0));
    expect(updatedCustomer?.currentDebt, equals(2000000.0));
  });
}
