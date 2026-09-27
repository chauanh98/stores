import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';
import 'package:stores/presentation/settings/pages/account_management_page.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';

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

class _FakeCustomerListNotifier extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

class _FakeSupplierListNotifier extends SupplierListNotifier {
  @override
  Future<List<Supplier>> build() async => [];
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('vi')],
      locale: const Locale('vi'),
      home: Material(child: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final mockStores = {
    'store_001': 'Chi nhánh Đông Thắng',
    'store_002': 'Chi nhánh Thới Bình',
  };

  group('CHALLENGER R1: Admin Scope Display Adversarial Edge Cases', () {
    testWidgets(
        'R1.1 Admin with storeId="store_001": MorePage renders "Toàn bộ chi nhánh"',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const admin = UserAccount(
        username: 'admin_store1',
        displayName: 'Admin Chi Nhánh 1',
        role: 'admin',
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => mockStores),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(<Order>[])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier()),
            supplierListNotifierProvider
                .overrideWith(() => _FakeSupplierListNotifier()),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            accountsListProvider
                .overrideWith((ref) => Stream.value(<UserAccount>[admin])),
            authProvider.overrideWith((ref) => _FakeAuthNotifier(admin)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('👑 Quản trị viên (Toàn hệ thống)'), findsOneWidget);
      expect(find.text('Toàn bộ chi nhánh'), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
      expect(find.text('Chi nhánh: Chi nhánh Đông Thắng'), findsNothing);
    });

    testWidgets(
        'R1.2 Admin with storeId="": MorePage renders "Toàn bộ chi nhánh"',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const admin = UserAccount(
        username: 'admin_empty',
        displayName: 'Admin Rỗng',
        role: 'admin',
        storeId: '',
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => mockStores),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(<Order>[])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier()),
            supplierListNotifierProvider
                .overrideWith(() => _FakeSupplierListNotifier()),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            accountsListProvider
                .overrideWith((ref) => Stream.value(<UserAccount>[admin])),
            authProvider.overrideWith((ref) => _FakeAuthNotifier(admin)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('👑 Quản trị viên (Toàn hệ thống)'), findsOneWidget);
      expect(find.text('Toàn bộ chi nhánh'), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
    });

    testWidgets(
        'R1.3 Admin with storeId="store_001" vs "all" vs "": AccountManagementPage renders "Toàn bộ chi nhánh (Toàn hệ thống)"',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const adminWithStore1 = UserAccount(
        username: 'admin_store1',
        displayName: 'Admin Chi Nhánh 1',
        role: 'admin',
        storeId: 'store_001',
      );
      const adminWithAll = UserAccount(
        username: 'admin_all',
        displayName: 'Admin Toàn Bộ',
        role: 'admin',
        storeId: 'all',
      );
      const adminWithEmpty = UserAccount(
        username: 'admin_empty',
        displayName: 'Admin Không Gán',
        role: 'admin',
        storeId: '',
      );

      final accounts = [adminWithStore1, adminWithAll, adminWithEmpty];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminWithStore1)),
            accountsListProvider.overrideWith((ref) => Stream.value(accounts)),
            availableStoresProvider.overrideWith((ref) async => mockStores),
          ],
          child: const AccountManagementPage(),
        ),
      );
      await tester.pumpAndSettle();

      // All 3 admin accounts must render 'Toàn bộ chi nhánh (Toàn hệ thống)'
      expect(
        find.text('Toàn bộ chi nhánh (Toàn hệ thống)'),
        findsNWidgets(3),
      );
      expect(find.text('Chi nhánh Đông Thắng'), findsNothing);
    });

    testWidgets(
        'R1.4 Owner account in MorePage: auto-normalized to admin scope with "all"',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const ownerAccount = UserAccount(
        username: 'owner_boss',
        displayName: 'Chủ Cửa Hàng Lớn',
        role: 'owner',
        storeId: 'store_002',
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => mockStores),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(<Order>[])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier()),
            supplierListNotifierProvider
                .overrideWith(() => _FakeSupplierListNotifier()),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            accountsListProvider
                .overrideWith((ref) => Stream.value(<UserAccount>[ownerAccount])),
            authProvider.overrideWith((ref) => _FakeAuthNotifier(ownerAccount)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('👑 Quản trị viên (Toàn hệ thống)'), findsOneWidget);
      expect(find.text('Toàn bộ chi nhánh'), findsOneWidget);
      expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
    });

    testWidgets(
        'R1.5 Owner account in AccountManagementPage: no dropdown assertion crash, normalized to admin scope with "all"',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const ownerAccount = UserAccount(
        username: 'owner_boss',
        displayName: 'Chủ Cửa Hàng Lớn',
        role: 'owner',
        storeId: 'store_002',
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(ownerAccount)),
            accountsListProvider
                .overrideWith((ref) => Stream.value([ownerAccount])),
            availableStoresProvider.overrideWith((ref) async => mockStores),
          ],
          child: const AccountManagementPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Toàn bộ chi nhánh (Toàn hệ thống)'), findsOneWidget);

      // Tap Edit button - must NOT throw Dropdown AssertionError
      final editBtn = find.byIcon(Icons.edit_outlined);
      expect(editBtn, findsOneWidget);
      await tester.tap(editBtn);
      await tester.pumpAndSettle();

      expect(find.text('Chỉnh sửa tài khoản'), findsOneWidget);
      // Dialog shows admin system-wide banner and current info banner
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Toàn bộ chi nhánh (Toàn hệ thống)'),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets(
        'R1.6 Staff account: shows assigned branch without bleeding admin scope',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const staffAccount = UserAccount(
        username: 'staff_dt',
        displayName: 'Nhân Viên ĐT',
        role: 'nhanvien',
        storeId: 'store_001',
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
            availableStoresProvider.overrideWith((ref) async => mockStores),
            allBranchesOrdersByDateRangeProvider
                .overrideWith((ref, range) => Stream.value(<Order>[])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier()),
            supplierListNotifierProvider
                .overrideWith(() => _FakeSupplierListNotifier()),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            accountsListProvider
                .overrideWith((ref) => Stream.value(<UserAccount>[staffAccount])),
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffAccount)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Nhân viên'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsNWidgets(2));
      expect(find.text('Toàn bộ chi nhánh'), findsNothing);
      expect(find.text('👑 Quản trị viên (Toàn hệ thống)'), findsNothing);
    });

    testWidgets(
        'R1.7 Supervisor account: shows assigned branch without bleeding admin scope',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const supervisorAccount = UserAccount(
        username: 'sup_tb',
        displayName: 'Giám Sát TB',
        role: 'supervisor',
        storeId: 'store_002',
      );

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            currentStoreNameProvider
                .overrideWith((ref) async => 'Chi nhánh Thới Bình'),
            availableStoresProvider.overrideWith((ref) async => mockStores),
            allBranchesOrdersByDateRangeProvider
              .overrideWith((ref, range) => Stream.value(<Order>[])),
            customerListNotifierProvider
                .overrideWith(() => _FakeCustomerListNotifier()),
            supplierListNotifierProvider
                .overrideWith(() => _FakeSupplierListNotifier()),
            productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
            accountsListProvider
                .overrideWith((ref) => Stream.value(<UserAccount>[supervisorAccount])),
            authProvider.overrideWith((ref) => _FakeAuthNotifier(supervisorAccount)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Giám sát'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsNWidgets(2));
      expect(find.text('Toàn bộ chi nhánh'), findsNothing);
      expect(find.text('👑 Quản trị viên (Toàn hệ thống)'), findsNothing);
    });

    testWidgets(
        'R1.8 Working branch label: dynamically updates when active store changes',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      const adminUser = UserAccount(
        username: 'admin1',
        displayName: 'Admin Toàn Chuỗi',
        role: 'admin',
        storeId: 'all',
      );

      final container = ProviderContainer(
        overrides: [
          currentStoreNameProvider
              .overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
          availableStoresProvider.overrideWith((ref) async => mockStores),
          allBranchesOrdersByDateRangeProvider
              .overrideWith((ref, range) => Stream.value(<Order>[])),
          customerListNotifierProvider
              .overrideWith(() => _FakeCustomerListNotifier()),
          supplierListNotifierProvider
              .overrideWith(() => _FakeSupplierListNotifier()),
          productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
          accountsListProvider
              .overrideWith((ref) => Stream.value(<UserAccount>[adminUser])),
          authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: Material(child: MorePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Initial active store: store_001
      expect(
        find.text('Đang làm việc: Chi nhánh Đông Thắng'),
        findsOneWidget,
      );

      // Now change selected store to store_002
      container.read(selectedStoreIdProvider.notifier).state = 'store_002';
      await tester.pumpAndSettle();

      // Working branch label must update to Chi nhánh Thới Bình
      expect(
        find.text('Đang làm việc: Chi nhánh Thới Bình'),
        findsOneWidget,
      );
      expect(
        find.text('Đang làm việc: Chi nhánh Đông Thắng'),
        findsNothing,
      );
    });
  });

  group('CHALLENGER R3: ListView Memory & Image Bounds Adversarial Tests', () {
    const inStockProduct = Product(
      id: 'prod_standard',
      name: 'Nước Tương Maggi 700ml',
      code: 'MAG01',
      price: 25000,
      costPrice: 18000,
      branchStocks: {'store_001': 40, 'store_002': 10},
      category: 'Gia vị',
      isCombo: false,
    );

    const componentA = Product(
      id: 'comp_a',
      name: 'Nước ngọt Pepsi 330ml',
      code: 'PEP01',
      price: 10000,
      costPrice: 7000,
      branchStocks: {'store_001': 20},
      category: 'Nước ngọt',
    );

    const componentB = Product(
      id: 'comp_b',
      name: 'Khoai tây Lay vị Tự Nhiên',
      code: 'LAY01',
      price: 15000,
      costPrice: 10000,
      branchStocks: {'store_001': 10},
      category: 'Snack',
    );

    const comboProduct = Product(
      id: 'prod_combo_party',
      name: 'Combo Party Cuối Tuần',
      code: 'CBPARTY',
      price: 30000,
      costPrice: 24000,
      branchStocks: {'store_001': 0},
      category: 'Combo',
      isCombo: true,
      comboComponents: [
        ComboComponent(
          productId: 'comp_a',
          productCode: 'PEP01',
          productName: 'Nước ngọt Pepsi 330ml',
          quantity: 2,
          costPrice: 7000,
        ),
        ComboComponent(
          productId: 'comp_b',
          productCode: 'LAY01',
          productName: 'Khoai tây Lay vị Tự Nhiên',
          quantity: 1,
          costPrice: 10000,
        ),
      ],
    );

    testWidgets(
        'R3.1 Non-combo product NEVER subscribes to productListProvider stream',
        (tester) async {
      final controller = StreamController<List<Product>>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            productListProvider.overrideWith((ref) => controller.stream),
          ],
          child: const ProductTile(product: inStockProduct),
        ),
      );
      await tester.pumpAndSettle();

      // Empirical proof: Non-combo product does NOT listen to productListProvider
      expect(
        controller.hasListener,
        isFalse,
        reason:
            'ProductTile subscribed to productListProvider for a non-combo product, causing O(N) memory listeners!',
      );

      // Verify product rendered correctly
      expect(find.text('Nước Tương Maggi 700ml'), findsOneWidget);
      expect(find.text('Tồn: 50'), findsOneWidget);

      // Even if controller emits 10 events, no listeners are triggered
      for (int i = 0; i < 10; i++) {
        controller.add([
          inStockProduct.copyWith(name: 'Modified $i'),
        ]);
      }
      await tester.pump();

      expect(controller.hasListener, isFalse);
      expect(find.text('Nước Tương Maggi 700ml'), findsOneWidget);
    });

    testWidgets(
        'R3.2 Combo product subscribes via select and updates only when available combo stock changes',
        (tester) async {
      final controller = StreamController<List<Product>>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            productListProvider.overrideWith((ref) => controller.stream),
          ],
          child: const ProductTile(product: comboProduct),
        ),
      );

      // Empirical proof: Combo product DOES listen to productListProvider
      expect(
        controller.hasListener,
        isTrue,
        reason: 'Combo product must listen to calculate composite stock',
      );

      // Initial state: A=20 (needs 2 -> 10 sets), B=10 (needs 1 -> 10 sets) => combo stock = 10
      controller.add([componentA, componentB, comboProduct]);
      await tester.pumpAndSettle();

      expect(find.text('Tồn bộ: 10'), findsOneWidget);
      expect(find.text('Còn hàng'), findsOneWidget);

      // Change unrelated product (component A and B untouched)
      controller.add([
        componentA,
        componentB,
        comboProduct,
        inStockProduct.copyWith(name: 'Unrelated Product Changed'),
      ]);
      await tester.pumpAndSettle();

      // Combo stock must remain 10
      expect(find.text('Tồn bộ: 10'), findsOneWidget);

      // Change component stock where combo stock actually changes:
      // Component A stock drops to 8 (8 / 2 = 4 sets, min(4, 10) = 4)
      controller.add([
        componentA.copyWith(branchStocks: {'store_001': 8}),
        componentB,
        comboProduct,
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Tồn bộ: 4'), findsOneWidget);

      // Change component stock to 0:
      // Component B stock drops to 0 => min(4, 0) = 0
      controller.add([
        componentA.copyWith(branchStocks: {'store_001': 8}),
        componentB.copyWith(branchStocks: {'store_001': 0}),
        comboProduct,
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Tồn bộ: 0'), findsOneWidget);
      expect(find.text('Hết hàng'), findsOneWidget);
    });

    testWidgets(
        'R3.3 ProductImageThumbnail: Default 150x150, Custom constraints, and Null unconstrained cache',
        (tester) async {
      // 1. Default constraints: 150x150
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: 'https://example.com/test_1.png',
            ),
          ),
        ),
      );
      final defaultImage = tester.widget<Image>(find.byType(Image));
      expect(defaultImage.image, isA<ResizeImage>());
      final resizeDefault = defaultImage.image as ResizeImage;
      expect(resizeDefault.width, equals(150));
      expect(resizeDefault.height, equals(150));

      // 2. Custom constraints: 80x60
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: 'https://example.com/test_2.png',
              cacheWidth: 80,
              cacheHeight: 60,
            ),
          ),
        ),
      );
      final customImage = tester.widget<Image>(find.byType(Image));
      expect(customImage.image, isA<ResizeImage>());
      final resizeCustom = customImage.image as ResizeImage;
      expect(resizeCustom.width, equals(80));
      expect(resizeCustom.height, equals(60));

      // 3. Null constraints: Unconstrained full resolution
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: 'https://example.com/test_3.png',
              cacheWidth: null,
              cacheHeight: null,
            ),
          ),
        ),
      );
      final unconstrainedImage = tester.widget<Image>(find.byType(Image));
      expect(unconstrainedImage.image, isA<NetworkImage>());
      expect(unconstrainedImage.image is ResizeImage, isFalse);
    });
  });
}
