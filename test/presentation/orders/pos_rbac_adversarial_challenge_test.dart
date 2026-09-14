import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';

// Mock HTTP client for image assets in tests
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

class _MockProductRepository implements ProductRepository {
  List<Product> products;
  Product? lastUpserted;
  int upsertCallCount = 0;

  _MockProductRepository(this.products);

  @override
  Future<void> delete(String id) async {
    products.removeWhere((p) => p.id == id);
  }

  @override
  Future<List<Product>> fetchAll() async => products;

  @override
  Future<Product?> fetchById(String id) async => products
      .cast<Product?>()
      .firstWhere((p) => p?.id == id, orElse: () => null);

  @override
  Future<void> updateStock(String id, int newStock) async {}

  @override
  Future<void> upsert(Product product) async {
    upsertCallCount++;
    lastUpserted = product;
    final idx = products.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      products[idx] = product;
    } else {
      products.add(product);
    }
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(products);
}

final _defaultBranches = [
  const Branch('branch_1', 'Chi nhánh Đông Thắng'),
  const Branch('branch_2', 'Chi nhánh Thời Bình'),
];

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      branchesProvider.overrideWithValue(_defaultBranches),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thời Bình',
          }),
      currentStoreNameProvider.overrideWith((ref) => 'Chi nhánh Đông Thắng'),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: child,
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _MockHttpOverrides();

  // Test accounts
  const supervisorUser = UserAccount(
    username: 'super_01',
    displayName: 'Tổng Quản Lý',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Cửa hàng trưởng',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên thu ngân',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const guestUser = UserAccount(
    username: 'guest_01',
    displayName: 'Khách',
    role: 'unknown_role',
    storeId: 'store_001',
  );

  // Test products
  const activeProduct1 = Product(
    id: 'prod_act_01',
    name: 'Nước tăng lực RedBull 250ml',
    code: 'RB250',
    barcode: '893000000001',
    brand: 'RedBull',
    price: 15000,
    costPrice: 10000,
    branchStocks: {'branch_1': 50, 'branch_2': 30},
    category: 'Đồ uống',
    allowSale: true,
  );

  const disabledProduct1 = Product(
    id: 'prod_dis_01',
    name: 'Sữa tươi hết hạn ngưng bán',
    code: 'MILK_EXPIRED',
    barcode: '893000000999',
    brand: 'Vinamilk',
    price: 35000,
    costPrice: 28000,
    branchStocks: {'branch_1': 20, 'branch_2': 10},
    category: 'Đồ uống',
    allowSale: false,
  );

  const disabledProduct2 = Product(
    id: 'prod_dis_02',
    name: 'Bánh snack cua cay ngừng nhập',
    code: 'SNACK_CRAB',
    barcode: '893000000888',
    brand: 'Oishi',
    price: 8000,
    costPrice: 5000,
    branchStocks: {'branch_1': 100, 'branch_2': 50},
    category: 'Bánh kẹo',
    allowSale: false,
  );

  group('CHALLENGE 1: Barcode Scanner & Search Bypass Attempts on POS', () {
    testWidgets('POS Catalog hides disabled products under all search modes (Barcode, Code, Name)',
        (tester) async {
      final catalog = [activeProduct1, disabledProduct1, disabledProduct2];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value(catalog)),
            cartProvider.overrideWith((ref) => CartNotifier()),
          ],
          child: const POSPage(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Initial State: Only active products are visible
      expect(find.text('Nước tăng lực RedBull 250ml'), findsOneWidget);
      expect(find.text('Sữa tươi hết hạn ngưng bán'), findsNothing);
      expect(find.text('Bánh snack cua cay ngừng nhập'), findsNothing);

      // 2. Search by disabled product barcode: "893000000999"
      final searchField = find.byType(TextField);
      expect(searchField, findsOneWidget);
      await tester.enterText(searchField, '893000000999');
      await tester.pumpAndSettle();

      // Inactive product MUST NOT be shown even if barcode matches exactly
      expect(find.text('Sữa tươi hết hạn ngưng bán'), findsNothing);
      expect(find.text('Không tìm thấy sản phẩm phù hợp'), findsOneWidget);

      // 3. Search by disabled product SKU code: "MILK_EXPIRED"
      await tester.enterText(searchField, 'MILK_EXPIRED');
      await tester.pumpAndSettle();
      expect(find.text('Sữa tươi hết hạn ngưng bán'), findsNothing);
      expect(find.text('Không tìm thấy sản phẩm phù hợp'), findsOneWidget);

      // 4. Search by disabled product partial name: "Sữa tươi"
      await tester.enterText(searchField, 'Sữa tươi');
      await tester.pumpAndSettle();
      expect(find.text('Sữa tươi hết hạn ngưng bán'), findsNothing);
      expect(find.text('Không tìm thấy sản phẩm phù hợp'), findsOneWidget);

      // 5. Search for active product barcode/SKU: "RB250"
      await tester.enterText(searchField, 'RB250');
      await tester.pumpAndSettle();
      expect(find.text('Nước tăng lực RedBull 250ml'), findsOneWidget);
    });

    test('CartNotifier direct manipulation strictly rejects disabled products', () {
      final cart = CartNotifier();

      // Direct addToCart call with disabled product
      cart.addToCart(disabledProduct1);
      expect(cart.state.isEmpty, isTrue,
          reason: 'Cart must reject disabled product on addToCart');

      // Direct addToCart call with another disabled product
      cart.addToCart(disabledProduct2);
      expect(cart.state.isEmpty, isTrue);

      // Attempt increaseQuantity on non-existent disabled product
      cart.increaseQuantity(disabledProduct1.id);
      expect(cart.state.isEmpty, isTrue);

      // Attempt updateQuantity on disabled product ID
      cart.updateQuantity(disabledProduct1.id, 10);
      expect(cart.state.isEmpty, isTrue);

      // Add valid active product
      cart.addToCart(activeProduct1);
      expect(cart.state.length, equals(1));
      expect(cart.state[activeProduct1.id]!.quantity, equals(1));

      // Attempt to add disabled product again while active product exists
      cart.addToCart(disabledProduct1);
      expect(cart.state.length, equals(1),
          reason: 'Disabled product must not be added to cart even if cart has items');
    });

    test('Large-scale synthetic catalog stress test: POS filters 50 active vs 50 disabled products', () {
      final activeList = List.generate(
        50,
        (i) => Product(
          id: 'act_$i',
          name: 'Active Product $i',
          code: 'ACT_$i',
          barcode: '893000$i',
          price: 10000.0 + i,
          costPrice: 7000.0,
          branchStocks: {'branch_1': 10},
          category: 'Category $i',
          allowSale: true,
        ),
      );

      final disabledList = List.generate(
        50,
        (i) => Product(
          id: 'dis_$i',
          name: 'Disabled Product $i',
          code: 'DIS_$i',
          barcode: '894000$i',
          price: 12000.0 + i,
          costPrice: 8000.0,
          branchStocks: {'branch_1': 5},
          category: 'Category $i',
          allowSale: false,
        ),
      );

      final fullCatalog = [...activeList, ...disabledList];

      // POS filter rule emulation
      final posVisible = fullCatalog.where((p) => p.allowSale).toList();
      expect(posVisible.length, equals(50));
      expect(posVisible.every((p) => p.allowSale), isTrue);
      expect(posVisible.any((p) => p.id.startsWith('dis_')), isFalse);

      // CartNotifier bulk addition stress test
      final cart = CartNotifier();
      for (final p in fullCatalog) {
        cart.addToCart(p);
      }
      expect(cart.state.length, equals(50));
      expect(cart.state.keys.every((id) => id.startsWith('act_')), isTrue);
    });
  });

  group('CHALLENGE 2: Role-Based Access Control (RBAC) & Escalation Defense', () {
    test('UserAccount role permissions matrix strictly enforced', () {
      // Supervisor: full access
      expect(supervisorUser.isSupervisor, isTrue);
      expect(supervisorUser.isAdmin, isTrue);
      expect(supervisorUser.isStaff, isFalse);
      expect(supervisorUser.canManageProducts, isTrue);
      expect(supervisorUser.canViewCostPrice, isTrue);

      // Admin: full product management, no cost price view
      expect(adminUser.isSupervisor, isFalse);
      expect(adminUser.isAdmin, isTrue);
      expect(adminUser.isStaff, isFalse);
      expect(adminUser.canManageProducts, isTrue);
      expect(adminUser.canViewCostPrice, isFalse);

      // Staff (nhanvien): blocked from product management
      expect(staffUser.isSupervisor, isFalse);
      expect(staffUser.isAdmin, isFalse);
      expect(staffUser.isStaff, isTrue);
      expect(staffUser.canManageProducts, isFalse);
      expect(staffUser.canViewCostPrice, isFalse);

      // Unknown / Guest role: blocked from product management
      expect(guestUser.isAdmin, isFalse);
      expect(guestUser.canManageProducts, isFalse);

      // Role formatting tolerance (case-insensitivity, trim)
      const dirtyAdmin = UserAccount(
        username: 'dirty_admin',
        role: '  ADMIN  ',
        storeId: 'store_001',
      );
      expect(dirtyAdmin.isAdmin, isTrue);
      expect(dirtyAdmin.canManageProducts, isTrue);

      const dirtySupervisor = UserAccount(
        username: 'dirty_super',
        role: 'Supervisor ',
        storeId: 'store_001',
      );
      expect(dirtySupervisor.isSupervisor, isTrue);
      expect(dirtySupervisor.isAdmin, isTrue);
      expect(dirtySupervisor.canManageProducts, isTrue);

      const dirtyStaff = UserAccount(
        username: 'dirty_staff',
        role: ' NhanVien ',
        storeId: 'store_001',
      );
      expect(dirtyStaff.isAdmin, isFalse);
      expect(dirtyStaff.canManageProducts, isFalse);
    });

    testWidgets('Staff in ProductDetailPage cannot toggle allowSale or edit product',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockRepo = _MockProductRepository([activeProduct1]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productRepositoryProvider.overrideWithValue(mockRepo),
            transactionsByProductProvider(activeProduct1.id)
                .overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: activeProduct1),
        ),
      );
      await tester.pumpAndSettle();

      // 1. SwitchListTile must have onChanged == null (disabled)
      final switchTile =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(switchTile.onChanged, isNull,
          reason: 'Switch must be disabled for staff');

      // 2. Edit button 'Sửa' must NOT exist in AppBar
      expect(find.text('Sửa'), findsNothing,
          reason: 'Staff must not have edit button');

      // 3. Delete button must NOT exist
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      // 4. Repository upsert must NOT have been called
      expect(mockRepo.upsertCallCount, equals(0));
    });

    testWidgets('Admin in ProductDetailPage can toggle allowSale and persists to Repository',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockRepo = _MockProductRepository([activeProduct1]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productRepositoryProvider.overrideWithValue(mockRepo),
            transactionsByProductProvider(activeProduct1.id)
                .overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: activeProduct1),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Switch must be enabled
      final switchTile =
          tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(switchTile.onChanged, isNotNull);
      expect(switchTile.value, isTrue);

      // 2. Edit button 'Sửa' must be present
      expect(find.text('Sửa'), findsOneWidget);

      // 3. Tap switch to disable product
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // 4. Verify repo upsert was called with allowSale == false
      expect(mockRepo.upsertCallCount, equals(1));
      expect(mockRepo.lastUpserted?.id, equals(activeProduct1.id));
      expect(mockRepo.lastUpserted?.allowSale, isFalse);
    });

    testWidgets('Staff in AddProductPage has disabled allowSale switch and warning banner',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockRepo = _MockProductRepository([]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const AddProductPage(),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Warning banner must be present
      expect(find.textContaining('Bạn không có quyền quản lý hàng hóa'),
          findsOneWidget);

      // 2. SwitchListTile for allowSale must be disabled
      final switchTile = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'Cho phép bán'));
      expect(switchTile.onChanged, isNull);
    });
  });

  group('CHALLENGE 3: Legacy Data Fallback & Serialization Integrity', () {
    test('ProductModel.fromMap fallback exhaustive matrix', () {
      // 1. Standard modern payload with allowSale: true
      final modernActive = ProductModel.fromMap({
        'id': 'm1',
        'name': 'Active Product',
        'allowSale': true,
      });
      expect(modernActive.allowSale, isTrue);

      // 2. Standard modern payload with allowSale: false
      final modernDisabled = ProductModel.fromMap({
        'id': 'm2',
        'name': 'Disabled Product',
        'allowSale': false,
      });
      expect(modernDisabled.allowSale, isFalse);

      // 3. Legacy payload with isActive: true, no allowSale
      final legacyActive = ProductModel.fromMap({
        'id': 'm3',
        'name': 'Legacy Active Product',
        'isActive': true,
      });
      expect(legacyActive.allowSale, isTrue);

      // 4. Legacy payload with isActive: false, no allowSale
      final legacyDisabled = ProductModel.fromMap({
        'id': 'm4',
        'name': 'Legacy Disabled Product',
        'isActive': false,
      });
      expect(legacyDisabled.allowSale, isFalse);

      // 5. Missing both allowSale and isActive (old Firebase record)
      final legacyUnspecified = ProductModel.fromMap({
        'id': 'm5',
        'name': 'Old Firebase Product',
        'stock': 25,
      });
      expect(legacyUnspecified.allowSale, isTrue,
          reason: 'Legacy records without active flag must default to true');

      // 6. Explicit null values in Map
      final nullFields = ProductModel.fromMap({
        'id': 'm6',
        'name': 'Null Fields Product',
        'allowSale': null,
        'isActive': null,
      });
      expect(nullFields.allowSale, isTrue);

      // 7. Conflicting fields: allowSale takes precedence over isActive
      final conflict1 = ProductModel.fromMap({
        'id': 'm7',
        'allowSale': false,
        'isActive': true,
      });
      expect(conflict1.allowSale, isFalse,
          reason: 'allowSale must take precedence over legacy isActive');

      final conflict2 = ProductModel.fromMap({
        'id': 'm8',
        'allowSale': true,
        'isActive': false,
      });
      expect(conflict2.allowSale, isTrue,
          reason: 'allowSale must take precedence over legacy isActive');

      // 8. Roundtrip serialization integrity
      const roundtripModel = ProductModel(
        id: 'rt_01',
        name: 'Roundtrip Test',
        code: 'RT01',
        price: 20000,
        costPrice: 15000,
        branchStocks: {'branch_1': 5},
        category: 'Test',
        allowSale: false,
      );
      final serialized = roundtripModel.toMap();
      expect(serialized['allowSale'], isFalse);

      final deserialized = ProductModel.fromMap(serialized);
      expect(deserialized.allowSale, isFalse);
      expect(deserialized.id, equals('rt_01'));
      expect(deserialized.price, equals(20000));
    });

    test('Product entity copyWith preserves and updates allowSale', () {
      const p = Product(
        id: 'p_copy',
        name: 'Copy Product',
        code: 'CP01',
        price: 10000,
        costPrice: 5000,
        branchStocks: {'branch_1': 1},
        category: 'General',
        allowSale: true,
      );

      final disabledCopy = p.copyWith(allowSale: false);
      expect(disabledCopy.allowSale, isFalse);
      expect(disabledCopy.isActive, isFalse);
      expect(disabledCopy.id, equals(p.id));

      final activeAgain = disabledCopy.copyWith(allowSale: true);
      expect(activeAgain.allowSale, isTrue);
      expect(activeAgain.isActive, isTrue);
    });
  });
}
