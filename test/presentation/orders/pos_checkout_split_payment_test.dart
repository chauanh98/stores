import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/orders/pages/pos_checkout_page.dart';

class _FakeOrderRepository implements OrderRepository {
  Order? lastCreatedOrder;

  @override
  Future<void> create(Order order) async {
    lastCreatedOrder = order;
  }

  @override
  Future<void> update(Order order) async {}

  @override
  Future<void> delete(String orderId) async {}

  @override
  Future<Order?> fetchById(String orderId) async => null;

  @override
  Stream<List<Order>> watchAll() => Stream.value([]);

  @override
  Stream<List<Order>> watchByCustomer(String customerId) => Stream.value([]);

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) => Stream.value([]);
}

class _FakeProductRepository implements ProductRepository {
  final Product product;
  _FakeProductRepository(this.product);

  @override
  Future<Product?> fetchById(String id) async => product;

  @override
  Future<List<Product>> fetchAll() async => [product];

  @override
  Stream<List<Product>> watchAll() => Stream.value([product]);

  @override
  Future<void> upsert(Product product) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> updateStock(String id, int newStock) async {}
}

class _FakeInventoryRepository implements InventoryRepository {
  @override
  Future<void> record(InventoryTransaction transaction) async {}

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
      DateTime startDate, DateTime endDate) =>
      Stream.value([]);

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value([]);
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

void main() {
  const sampleProduct = Product(
    id: 'p1',
    name: 'Bàn phím cơ AKKO',
    code: 'AKKO3087',
    price: 1000000,
    costPrice: 700000,
    category: 'Keyboard',
    branchStocks: {'store_001': 10},
    allowSale: true,
  );

  const testConfig = StorePaymentConfig(
    storeId: 'store_001',
    storeName: 'Đông Thắng Store',
    address: '123 ĐT',
    phone: '0900000000',
    bankName: 'MBBank',
    bankId: 'mbbank',
    accountNo: '999988887777',
    accountName: 'TEST STORE',
    footerNote: 'Hẹn gặp lại',
  );

  Widget buildCheckoutPage(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('vi'),
        home: POSCheckoutPage(),
      ),
    );
  }

  group('POSCheckoutPage Split Payment & Quick Cash Tests', () {
    testWidgets('Displays Quick Cash Chips, Order Note, and Split Payment option', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeOrderRepo = _FakeOrderRepository();
      final fakeProductRepo = _FakeProductRepository(sampleProduct);
      final fakeInvRepo = _FakeInventoryRepository();

      final container = ProviderContainer(
        overrides: [
          orderRepositoryProvider.overrideWithValue(fakeOrderRepo),
          productRepositoryProvider.overrideWithValue(fakeProductRepo),
          inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
          storePaymentConfigProvider.overrideWithValue(testConfig),
          selectedPOSBranchProvider.overrideWith((ref) => 'store_001'),
          authProvider.overrideWith((ref) => _FakeAuthNotifier(const UserAccount(
                username: 'admin',
                displayName: 'Admin User',
                role: 'admin',
                storeId: 'store_001',
              ))),
          productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
        ],
      );
      addTearDown(container.dispose);

      // Add product to cart (1 x 1,000,000đ)
      container.read(cartProvider.notifier).addToCart(sampleProduct);

      await tester.pumpWidget(buildCheckoutPage(container));
      await tester.pumpAndSettle();

      // Verify Quick Cash Chips generated for 1,000,000đ
      expect(find.text('Gợi ý tiền mặt thông minh:'), findsOneWidget);
      expect(find.text('1.000.000 đ (Trả đủ)'), findsOneWidget);

      // Verify Order Note field
      expect(find.text('Ghi chú đơn hàng'), findsOneWidget);

      // Verify Payment method dropdown has Split option
      expect(find.text('Tiền mặt'), findsOneWidget);
      await tester.ensureVisible(find.text('Tiền mặt'));
      await tester.tap(find.text('Tiền mặt'));
      await tester.pumpAndSettle();

      expect(find.text('Kết hợp (TM + CK)'), findsOneWidget);
      await tester.tap(find.text('Kết hợp (TM + CK)').last);
      await tester.pumpAndSettle();

      // Split dual input fields should appear
      expect(find.text('Tiền mặt đưa'), findsOneWidget);
      expect(find.text('Chuyển khoản (VietQR)'), findsOneWidget);
    });

    testWidgets('Split mode dual inputs auto-balance and submit order with split values and note', (tester) async {
      tester.view.physicalSize = const Size(1200, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeOrderRepo = _FakeOrderRepository();
      final fakeProductRepo = _FakeProductRepository(sampleProduct);
      final fakeInvRepo = _FakeInventoryRepository();

      final container = ProviderContainer(
        overrides: [
          orderRepositoryProvider.overrideWithValue(fakeOrderRepo),
          productRepositoryProvider.overrideWithValue(fakeProductRepo),
          inventoryRepositoryProvider.overrideWithValue(fakeInvRepo),
          storePaymentConfigProvider.overrideWithValue(testConfig),
          selectedPOSBranchProvider.overrideWith((ref) => 'store_001'),
          authProvider.overrideWith((ref) => _FakeAuthNotifier(const UserAccount(
                username: 'admin',
                displayName: 'Admin User',
                role: 'admin',
                storeId: 'store_001',
              ))),
          activeOrderIdProvider.overrideWith((ref) => 'HD_SPLIT_001'),
          productListProvider.overrideWith((ref) => Stream.value([sampleProduct])),
        ],
      );
      addTearDown(container.dispose);

      // Add product (1 x 1,000,000đ)
      container.read(cartProvider.notifier).addToCart(sampleProduct);

      await tester.pumpWidget(buildCheckoutPage(container));
      await tester.pumpAndSettle();

      // Enter order note
      final noteFinder = find.widgetWithText(TextField, 'Nhập ghi chú cho đơn hàng (nếu có)...');
      await tester.ensureVisible(noteFinder);
      await tester.enterText(noteFinder, 'Khách lấy hóa đơn đỏ');
      await tester.pumpAndSettle();

      // Switch to split payment
      await tester.ensureVisible(find.text('Tiền mặt'));
      await tester.tap(find.text('Tiền mặt'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Kết hợp (TM + CK)').last);
      await tester.pumpAndSettle();

      // Enter 400,000đ into Tiền mặt đưa
      final cashRowFinder = find.ancestor(of: find.text('Tiền mặt đưa'), matching: find.byType(Row));
      final cashInputFinder = find.descendant(of: cashRowFinder, matching: find.byType(TextField));
      await tester.ensureVisible(cashInputFinder);
      await tester.enterText(cashInputFinder, '400000');
      await tester.pumpAndSettle();

      // Tap Checkout / Thanh toán button
      await tester.tap(find.widgetWithText(ElevatedButton, 'Thanh toán'));
      await tester.pumpAndSettle();

      // Verify order submitted to repo
      final created = fakeOrderRepo.lastCreatedOrder;
      expect(created, isNotNull);
      expect(created!.paymentMethod, 'split');
      expect(created.cashAmount, 400000.0);
      expect(created.transferAmount, 600000.0);
      expect(created.amountPaid, 1000000.0);
      expect(created.note, 'Khách lấy hóa đơn đỏ');
    });
  });
}
