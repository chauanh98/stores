import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';

// Mock HTTP client for widget tests with images
final _transparentPixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82
];

class _MockHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;
  @override
  int get contentLength => _transparentPixelPng.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream.value(_transparentPixelPng).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockProductRepository implements ProductRepository {
  final Map<String, Product> products;

  _MockProductRepository(List<Product> list)
      : products = {for (final p in list) p.id: p};

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();
  @override
  Future<Product?> fetchById(String id) async => products[id];
  @override
  Future<void> updateStock(String id, int newStock) async {}
  @override
  Future<void> upsert(Product product) async {
    products[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    products.remove(id);
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());
}

class _MockOrderRepository implements OrderRepository {
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

class _MockCustomerRepository implements CustomerRepository {
  final Map<String, Customer> customers = {};

  @override
  Future<Customer?> fetchById(String id) async => customers[id];
  @override
  Future<void> upsert(Customer customer) async {
    customers[customer.id] = customer;
  }

  @override
  Future<void> delete(String id) async {
    customers.remove(id);
  }

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());
}

class _FakeCustomerListNotifier
    extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];

  @override
  Future<void> refresh() async {}
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
  setUpAll(() {
    HttpOverrides.global = _MockHttpOverrides();
  });

  tearDownAll(() {
    HttpOverrides.global = null;
  });

  setUp(() {
    MultiCartNotifier.resetBranchCartsCache();
  });

  const testProductBAB1 = Product(
    id: 'BAB1',
    code: 'BAB1',
    name: 'Bộ bàn ăn bên DÀY - oval - 8 ghế',
    price: 28000000,
    costPrice: 19800000,
    branchStocks: {
      'store_001': 0, // Đông Thắng = 0
      'store_002': 4, // Thới Bình = 4
    },
    category: 'Bàn ăn',
    brand: 'Khác',
    model: 'Khác',
    type: 'Hàng hóa',
    unit: 'Cái',
    minStock: 0,
    allowSale: true,
  );

  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản Trị Viên',
    role: 'admin',
    storeId: 'store_002', // Active store = Thới Bình
  );

  Widget createTestWidget({
    required List<Product> products,
    required UserAccount user,
    String? initialPOSBranch,
  }) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
        productRepositoryProvider
            .overrideWithValue(_MockProductRepository(products)),
        orderRepositoryProvider.overrideWithValue(_MockOrderRepository()),
        customerRepositoryProvider.overrideWithValue(_MockCustomerRepository()),
        customerListNotifierProvider
            .overrideWith(() => _FakeCustomerListNotifier()),
        availableStoresProvider.overrideWith((ref) async => {
              'store_001': 'Chi nhánh Đông Thắng',
              'store_002': 'Chi nhánh Thới Bình',
            }),
        if (initialPOSBranch != null)
          selectedPOSBranchProvider.overrideWith((ref) => initialPOSBranch),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: Locale('vi'),
        home: POSPage(),
      ),
    );
  }

  group('BAB1 Branch Stock & Cart Isolation Tests', () {
    testWidgets(
        'BAB1 cart is isolated per branch: adding in Thới Bình does not carry over to Đông Thắng',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Khởi tạo POSPage ở Thới Bình (store_002)
      await tester.pumpWidget(createTestWidget(
        products: [testProductBAB1],
        user: adminUser,
        initialPOSBranch: 'store_002',
      ));
      await tester.pumpAndSettle();

      // Tại Thới Bình (store_002): tồn kho = 4, hiển thị "Còn hàng"
      expect(find.text('Bộ bàn ăn bên DÀY - oval - 8 ghế'), findsOneWidget);
      expect(find.text('Còn hàng'), findsOneWidget);

      // Thêm BAB1 vào giỏ hàng tại Thới Bình
      final addIconFinder = find.byKey(const Key('pos_add_to_cart_BAB1'));
      expect(addIconFinder, findsOneWidget);
      await tester.tap(addIconFinder);
      await tester.pumpAndSettle();

      // Kiểm tra giỏ hàng tại Thới Bình đã có 1 sản phẩm
      expect(find.byIcon(Icons.remove), findsOneWidget); // Nút trừ xuất hiện khi đã có trong giỏ
      expect(find.textContaining('Giỏ hàng'), findsOneWidget);

      // Chuyển sang Chi nhánh Đông Thắng (store_001) thông qua AppBar branch switcher
      final branchSwitchFinder = find.text('Chi nhánh Thới Bình');
      expect(branchSwitchFinder, findsOneWidget);
      await tester.tap(branchSwitchFinder);
      await tester.pumpAndSettle();

      // Chọn Đông Thắng trong bottom sheet
      final dongThangOption = find.text('Chi nhánh Đông Thắng');
      expect(dongThangOption, findsOneWidget);
      await tester.tap(dongThangOption);
      await tester.pumpAndSettle();

      // Xác nhận chi nhánh hiển thị hiện tại là Đông Thắng
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);

      // TẠI ĐÔNG THẮNG:
      // 1. Giỏ hàng của Đông Thắng hoàn toàn độc lập, không có BAB1 từ Thới Bình!
      expect(find.textContaining('Giỏ hàng'), findsNothing);

      // 2. Tồn kho của BAB1 tại Đông Thắng = 0, hiển thị badge "Hết hàng"
      expect(find.text('Hết hàng'), findsOneWidget);

      // 3. Số lượng hiển thị trong giỏ cho BAB1 tại Đông Thắng là 0 (nút tròn Icon(Icons.add) thay vì bộ tăng giảm [- 1 +])
      expect(find.byIcon(Icons.remove), findsNothing);

      // 4. Nhấn liên tiếp nút thêm hàng tại Đông Thắng (khi tồn = 0)
      final addOutOfStockFinder = find.byKey(const Key('pos_add_to_cart_BAB1'));
      expect(addOutOfStockFinder, findsOneWidget);

      // Táp 3 lần liên tiếp
      await tester.tap(addOutOfStockFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(addOutOfStockFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(addOutOfStockFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Xác nhận có thông báo "Sản phẩm đã hết hàng trong kho!"
      expect(find.text('Sản phẩm đã hết hàng trong kho!'), findsOneWidget);

      // 5. Chuyển lại về Thới Bình (store_002)
      final branchSwitchBackFinder = find.text('Chi nhánh Đông Thắng');
      await tester.tap(branchSwitchBackFinder);
      await tester.pumpAndSettle();

      final thoiBinhOption = find.text('Chi nhánh Thới Bình');
      await tester.tap(thoiBinhOption);
      await tester.pumpAndSettle();

      // Hóa đơn lưu tạm tại Thới Bình vẫn còn nguyên vẹn 1 sản phẩm BAB1
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.textContaining('Giỏ hàng'), findsOneWidget);
      expect(find.byIcon(Icons.remove), findsOneWidget);
      // Tồn kho hiển thị tại Thới Bình là Còn hàng (không bị gán Hết hàng do Đông Thắng)
      expect(find.text('Còn hàng'), findsOneWidget);
      expect(find.text('Hết hàng'), findsNothing);

      // Tăng số lượng BAB1 tại Thới Bình thành công (từ 1 lên 2)
      final addMoreFinder = find.byWidgetPredicate(
          (w) => w is Icon && w.icon == Icons.add && w.size == 14);
      expect(addMoreFinder, findsOneWidget);
      await tester.tap(addMoreFinder);
      await tester.pumpAndSettle();
      expect(find.text('2'), findsNWidgets(2));
    });

    testWidgets(
        'Supervisor role can switch between Thới Bình and Đông Thắng without BAB1 getting out of stock on return',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      const supervisor = UserAccount(
        username: 'supervisor_user',
        displayName: 'Giám Sát Viên',
        role: 'supervisor',
        storeId: 'store_001',
      );

      expect(supervisor.canSwitchStore, isTrue);

      // Khởi tạo POSPage ở Thới Bình (store_002) cho Supervisor
      await tester.pumpWidget(createTestWidget(
        products: [testProductBAB1],
        user: supervisor,
        initialPOSBranch: 'store_002',
      ));
      await tester.pumpAndSettle();

      // Tại Thới Bình: hiển thị Còn hàng
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('Còn hàng'), findsOneWidget);
      expect(find.text('Hết hàng'), findsNothing);

      // Chuyển sang Đông Thắng (store_001)
      await tester.tap(find.text('Chi nhánh Thới Bình'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chi nhánh Đông Thắng'));
      await tester.pumpAndSettle();

      // Tại Đông Thắng: Tồn kho = 0, hiển thị "Hết hàng"
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);

      // Chuyển lại về Thới Bình (store_002)
      await tester.tap(find.text('Chi nhánh Đông Thắng'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Chi nhánh Thới Bình'));
      await tester.pumpAndSettle();

      // Tại Thới Bình: BAB1 lập tức hiển thị "Còn hàng", KHÔNG bị báo "Hết hàng"
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('Còn hàng'), findsOneWidget);
      expect(find.text('Hết hàng'), findsNothing);

      // Thêm vào giỏ thành công tại Thới Bình
      final addFinder = find.byKey(const Key('pos_add_to_cart_BAB1'));
      expect(addFinder, findsOneWidget);
      await tester.tap(addFinder);
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.remove), findsOneWidget);
      expect(find.textContaining('Giỏ hàng'), findsOneWidget);
    });

    test('MultiCartNotifier correctly caches and isolates tabs per branch in pure Dart unit test',
        () {
      final notifier1 = MultiCartNotifier(currentBranchId: 'store_002');
      notifier1.addToCart(testProductBAB1, quantity: 2);
      expect(notifier1.state.activeTab.totalItems, equals(2));
      expect(notifier1.state.activeTab.items.containsKey('BAB1'), isTrue);

      // Switch to store_001
      final notifier2 = MultiCartNotifier(currentBranchId: 'store_001');
      expect(notifier2.state.activeTab.totalItems, equals(0));
      expect(notifier2.state.activeTab.items.isEmpty, isTrue);

      // Add different item in store_001
      const otherProduct = Product(
        id: 'OTHER',
        code: 'OTHER',
        name: 'Other Product',
        price: 10000,
        costPrice: 5000,
        branchStocks: {'store_001': 10},
        category: 'Test',
        allowSale: true,
      );
      notifier2.addToCart(otherProduct, quantity: 1);
      expect(notifier2.state.activeTab.totalItems, equals(1));

      // Switch back to store_002
      final notifier3 = MultiCartNotifier(currentBranchId: 'store_002');
      expect(notifier3.state.activeTab.totalItems, equals(2));
      expect(notifier3.state.activeTab.items['BAB1']!.quantity, equals(2));
    });
  });
}
