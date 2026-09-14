import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/product_unit.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';

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

class FakeProductRepository implements ProductRepository {
  final List<Product> products;
  Product? lastUpsertedProduct;
  String? lastDeletedId;

  FakeProductRepository([List<Product>? initial])
      : products = initial != null ? List<Product>.from(initial) : [];

  @override
  Stream<List<Product>> watchAll() => Stream.value(products);

  @override
  Future<List<Product>> fetchAll() async => products;

  @override
  Future<Product?> fetchById(String id) async {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Product product) async {
    lastUpsertedProduct = product;
    final index = products.indexWhere((p) => p.id == product.id);
    if (index >= 0) {
      products[index] = product;
    } else {
      products.add(product);
    }
  }

  @override
  Future<void> delete(String id) async {
    lastDeletedId = id;
    products.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final index = products.indexWhere((p) => p.id == id);
    if (index >= 0) {
      products[index] = products[index].copyWith(
        branchStocks: {'branch_1': newStock, 'branch_2': 0},
      );
    }
  }
}

Widget _buildTestApp({
  required Widget child,
  required UserAccount user,
  FakeProductRepository? repo,
  List<Category>? categories,
}) {
  final fakeRepo = repo ?? FakeProductRepository();
  final cats = categories ??
      [
        const Category(id: 'cat_01', name: 'Đồ uống'),
        const Category(id: 'cat_02', name: 'Bánh kẹo'),
      ];

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
      productRepositoryProvider.overrideWithValue(fakeRepo),
      productListProvider
          .overrideWith((ref) => Stream.value(fakeRepo.products)),
      categoryListProvider.overrideWith((ref) => Stream.value(cats)),
      currentStoreIdProvider.overrideWithValue('store_001'),
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
  const supervisorUser = UserAccount(
    username: 'supervisor_01',
    displayName: 'Quản lý Tổng',
    role: 'supervisor',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên Bán hàng',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const sampleExistingProduct = Product(
    id: 'prod_existing_01',
    name: 'Bia Saigon Special 330ml',
    code: 'SP000001',
    barcode: '893111111001',
    brand: 'Sabeco',
    price: 15000,
    costPrice: 11000,
    branchStocks: {'branch_1': 50, 'branch_2': 20},
    category: 'Đồ uống',
    category3Levels: 'Đồ uống >> Bia',
    unit: 'Lon',
    minStock: 10,
    maxStock: 200,
    description: 'Bia lon chất lượng cao',
    units: [
      ProductUnit(
        id: 'u_loc_01',
        unitName: 'Lốc (6 lon)',
        conversionRate: 6,
        price: 88000,
        costPrice: 65000,
        barcode: '893111111006',
        code: 'BSG-LOC6',
      ),
      ProductUnit(
        id: 'u_thung_01',
        unitName: 'Thùng (24 lon)',
        conversionRate: 24,
        price: 345000,
        costPrice: 260000,
        barcode: '893111111024',
        code: 'BSG-THUNG24',
      ),
    ],
  );

  group('AddProductPage - Form Validation & Basic Inputs', () {
    testWidgets('Validates required product name field on save',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
          repo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Title should be "Hàng hóa mới"
      expect(find.text('Hàng hóa mới'), findsOneWidget);

      // Tap "Lưu" with empty fields
      final saveBtn = find.widgetWithText(TextButton, 'Lưu');
      expect(saveBtn, findsOneWidget);
      await tester.tap(saveBtn);
      await tester.pumpAndSettle();

      // Expect validation error for empty name
      expect(find.text('Vui lòng nhập Tên hàng *'), findsOneWidget);
      expect(fakeRepo.lastUpsertedProduct, isNull);
    });

    testWidgets('Validates category selection on save', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
          repo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Enter product name
      final nameField = find.widgetWithText(TextFormField, 'Tên hàng *');
      await tester.enterText(nameField, 'Bánh Snack Khoai Tây');

      // Attempt save without selecting category
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      // SnackBar prompt to select category
      expect(find.text('Vui lòng chọn nhóm hàng!'), findsOneWidget);
      expect(fakeRepo.lastUpsertedProduct, isNull);
    });
  });

  group('AddProductPage - SKU Auto-generation & Barcode Scanner', () {
    testWidgets('1-Click auto-generates next SKU code from existing products',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeProductRepository([
        sampleExistingProduct,
        const Product(
          id: 'prod_02',
          name: 'Nước ngọt Pepsi',
          code: 'SP000002',
          price: 10000,
          costPrice: 7000,
          branchStocks: {'branch_1': 10},
          category: 'Đồ uống',
        ),
      ]);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
          repo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Find auto-gen button (Icons.auto_awesome)
      final autoGenBtn = find.byIcon(Icons.auto_awesome);
      expect(autoGenBtn, findsOneWidget);

      await tester.tap(autoGenBtn);
      await tester.pumpAndSettle();

      // Next code after SP000001 and SP000002 should be SP000003
      final skuField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Mã hàng (SKU)'));
      expect(skuField.controller?.text, equals('SP000003'));
    });

    testWidgets('Allows manual typing and override in SKU field',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
        ),
      );
      await tester.pumpAndSettle();

      final skuField = find.widgetWithText(TextFormField, 'Mã hàng (SKU)');
      await tester.enterText(skuField, 'CUSTOM-SKU-999');
      await tester.pumpAndSettle();

      final fieldWidget = tester.widget<TextFormField>(skuField);
      expect(fieldWidget.controller?.text, equals('CUSTOM-SKU-999'));
    });

    testWidgets('Opens Barcode Scanner Dialog and updates barcode',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
        ),
      );
      await tester.pumpAndSettle();

      final scanBtn = find.byIcon(Icons.qr_code_scanner);
      expect(scanBtn, findsOneWidget);

      await tester.tap(scanBtn);
      await tester.pumpAndSettle();

      // Dialog appears
      expect(find.text('Quét mã vạch'), findsOneWidget);

      // Enter scanned barcode
      final dialogBarcodeField =
          find.widgetWithText(TextField, 'Mã vạch (Barcode)');
      await tester.enterText(dialogBarcodeField, '893888888999');

      // Confirm
      await tester.tap(find.widgetWithText(FilledButton, 'Xác nhận'));
      await tester.pumpAndSettle();

      // Main field updated
      final barcodeField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Mã vạch'));
      expect(barcodeField.controller?.text, equals('893888888999'));
    });
  });

  group('AddProductPage - Cost Price Role-Gating', () {
    testWidgets(
        'Supervisor sees and can edit Cost Price input', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
        ),
      );
      await tester.pumpAndSettle();

      // Cost price field is visible
      expect(find.widgetWithText(TextFormField, 'Giá vốn'), findsOneWidget);

      await tester.enterText(
          find.widgetWithText(TextFormField, 'Giá vốn'), '125000');
      await tester.pumpAndSettle();

      final costField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Giá vốn'));
      expect(costField.controller?.text, equals('125000'));
    });

    testWidgets('Staff CANNOT see Cost Price input (hidden/masked)',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: staffUser,
        ),
      );
      await tester.pumpAndSettle();

      // Cost price input MUST NOT exist for staff
      expect(find.widgetWithText(TextFormField, 'Giá vốn'), findsNothing);
    });

    testWidgets('Admin CANNOT see Cost Price input (hidden for admin too)',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: adminUser,
        ),
      );
      await tester.pumpAndSettle();

      // Cost price input MUST NOT exist for admin
      expect(find.widgetWithText(TextFormField, 'Giá vốn'), findsNothing);
    });
  });

  group('AddProductPage - Units Conversion Management', () {
    testWidgets(
        'Allows setting Base Unit and adding secondary conversion units with rate, price, and barcode',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
          repo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Base unit field
      final baseUnitField = find.widgetWithText(
          TextFormField, 'Đơn vị cơ bản (Mặc định) *');
      expect(baseUnitField, findsOneWidget);
      await tester.enterText(baseUnitField, 'Lon');
      await tester.pumpAndSettle();

      // Tap "+ Thêm ĐVT quy đổi"
      final addUnitBtn = find.text('Thêm ĐVT quy đổi');
      expect(addUnitBtn, findsOneWidget);
      await tester.tap(addUnitBtn);
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Thêm đơn vị quy đổi'), findsOneWidget);

      // Fill unit fields
      await tester.enterText(
          find.widgetWithText(TextField, 'Tên đơn vị quy đổi *'), 'Lốc');
      await tester.enterText(
          find.widgetWithText(TextField, 'Tỷ lệ quy đổi *'), '6');
      await tester.enterText(
          find.widgetWithText(TextField, 'Giá bán quy đổi *'), '88000');
      await tester.enterText(
          find.widgetWithText(TextField, 'Mã vạch đơn vị (Barcode)'),
          '893111111006');
      await tester.enterText(
          find.widgetWithText(TextField, 'Mã SKU đơn vị'), 'BSG-LOC6');

      // Submit dialog
      await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
      await tester.pumpAndSettle();

      // Verify unit is added to table/list
      expect(find.text('Lốc'), findsOneWidget);
      expect(find.textContaining('1 Lốc = 6 Lon • Giá bán: 88.000 đ'),
          findsOneWidget);
      expect(find.textContaining('Barcode: 893111111006'), findsOneWidget);
      expect(find.textContaining('SKU: BSG-LOC6'), findsOneWidget);
    });

    testWidgets('Allows editing and deleting an existing unit from table',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(initialProduct: sampleExistingProduct),
          user: supervisorUser,
        ),
      );
      await tester.pumpAndSettle();

      // Preloaded units
      expect(find.text('Lốc (6 lon)'), findsOneWidget);
      expect(find.text('Thùng (24 lon)'), findsOneWidget);

      // Tap delete on the second unit
      final deleteIcons = find.byIcon(Icons.delete_outline);
      expect(deleteIcons, findsWidgets);
      await tester.tap(deleteIcons.last);
      await tester.pumpAndSettle();

      // Second unit removed
      expect(find.text('Thùng (24 lon)'), findsNothing);
      expect(find.text('Lốc (6 lon)'), findsOneWidget);
    });
  });

  group('AddProductPage - Min / Max Stock Limits', () {
    testWidgets('Inputs for minStock and maxStock are saved into Product',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeProductRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
          repo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Fill basic required fields
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên hàng *'), 'Sữa tươi Vinamilk');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Giá bán'), '35000');

      // Select Category
      await tester.tap(find.widgetWithText(InputDecorator, 'Chọn nhóm hàng *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đồ uống').first);
      await tester.pumpAndSettle();

      // Fill Min / Max stock
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tồn tối thiểu'), '15');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tồn tối đa'), '350');

      // Save
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastUpsertedProduct, isNotNull);
      final saved = fakeRepo.lastUpsertedProduct!;
      expect(saved.name, equals('Sữa tươi Vinamilk'));
      expect(saved.category, equals('Đồ uống'));
      expect(saved.minStock, equals(15));
      expect(saved.maxStock, equals(350));
    });
  });

  group('AddProductPage - Permission Guarding (canManageProducts)', () {
    testWidgets(
        'Staff has access denied banner, disabled inputs, and disabled Save button',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: staffUser,
        ),
      );
      await tester.pumpAndSettle();

      // Banner is shown
      expect(
          find.text(
              'Bạn không có quyền quản lý hàng hóa (chỉ xem). Vui lòng liên hệ Quản lý để thao tác.'),
          findsOneWidget);
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);

      // Save button is disabled
      final saveBtn =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Lưu'));
      expect(saveBtn.onPressed, isNull);

      // Name field is disabled
      final nameField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Tên hàng *'));
      expect(nameField.enabled, isFalse);
    });

    testWidgets(
        'Supervisor has full management access with enabled Save button',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
        ),
      );
      await tester.pumpAndSettle();

      // Banner is NOT shown
      expect(find.byIcon(Icons.lock_outline), findsNothing);

      // Save button is enabled
      final saveBtn =
          tester.widget<TextButton>(find.widgetWithText(TextButton, 'Lưu'));
      expect(saveBtn.onPressed, isNotNull);

      // Name field is enabled
      final nameField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Tên hàng *'));
      expect(nameField.enabled, isTrue);
    });
  });

  group('AddProductPage - Edit Existing Product Integration', () {
    testWidgets(
        'Pre-populates all fields and saves updated entity with units and stock limits',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeProductRepository([sampleExistingProduct]);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(product: sampleExistingProduct),
          user: supervisorUser,
          repo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Title should be "Chỉnh sửa sản phẩm"
      expect(find.text('Chỉnh sửa sản phẩm'), findsOneWidget);

      // Prepopulated fields
      final nameField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Tên hàng *'));
      expect(nameField.controller?.text, equals('Bia Saigon Special 330ml'));

      final skuField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Mã hàng (SKU)'));
      expect(skuField.controller?.text, equals('SP000001'));

      final priceField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Giá bán'));
      expect(priceField.controller?.text, equals('15000'));

      final costField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Giá vốn'));
      expect(costField.controller?.text, equals('11000'));

      final minStockField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Tồn tối thiểu'));
      expect(minStockField.controller?.text, equals('10'));

      final maxStockField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Tồn tối đa'));
      expect(maxStockField.controller?.text, equals('200'));

      // Units preloaded
      expect(find.text('Lốc (6 lon)'), findsOneWidget);
      expect(find.text('Thùng (24 lon)'), findsOneWidget);

      // Update name and price
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên hàng *'),
          'Bia Saigon Special 330ml (Lon Cao)');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Giá bán'), '16500');

      // Save
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastUpsertedProduct, isNotNull);
      final updated = fakeRepo.lastUpsertedProduct!;
      expect(updated.id, equals('prod_existing_01'));
      expect(updated.name, equals('Bia Saigon Special 330ml (Lon Cao)'));
      expect(updated.price, equals(16500.0));
      expect(updated.costPrice, equals(11000.0));
      expect(updated.units.length, equals(2));
      expect(updated.minStock, equals(10));
      expect(updated.maxStock, equals(200));
    });

    testWidgets(
        'Admin edits existing product preserves original cost price when cost price is hidden',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final fakeRepo = FakeProductRepository([sampleExistingProduct]);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(product: sampleExistingProduct),
          user: adminUser, // Admin can manage products, but CANNOT view/edit cost price
          repo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Cost price is hidden
      expect(find.widgetWithText(TextFormField, 'Giá vốn'), findsNothing);

      // Admin updates selling price
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Giá bán'), '18000');

      // Save
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      expect(fakeRepo.lastUpsertedProduct, isNotNull);
      final updated = fakeRepo.lastUpsertedProduct!;
      expect(updated.price, equals(18000.0));
      // Original cost price (11000.0) MUST remain preserved and uncorrupted!
      expect(updated.costPrice, equals(11000.0));
    });
  });

  group('AddProductPage - Combo & Attributes Integration', () {
    testWidgets(
        'Allows toggling Combo mode and configuring components with suggested cost',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const componentProd = Product(
        id: 'comp_01',
        name: 'Bánh que Pocky',
        code: 'PK01',
        price: 12000,
        costPrice: 8000,
        branchStocks: {'branch_1': 10},
        category: 'Bánh kẹo',
      );
      final fakeRepo = FakeProductRepository([componentProd]);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
          repo: fakeRepo,
        ),
      );
      await tester.pumpAndSettle();

      // Toggle combo switch
      final comboSwitch =
          find.widgetWithText(SwitchListTile, 'Sản phẩm Combo / Bộ');
      expect(comboSwitch, findsOneWidget);
      await tester.tap(comboSwitch);
      await tester.pumpAndSettle();

      // Stock field is replaced with combo explanation
      expect(
          find.text(
              'Tồn kho của Combo không cần nhập, hệ thống sẽ tự động tính dựa trên số lượng linh kiện thành phần.'),
          findsOneWidget);

      // Open component selector
      final addCompBtn = find.text('Thêm linh kiện');
      expect(addCompBtn, findsOneWidget);
      await tester.tap(addCompBtn);
      await tester.pumpAndSettle();

      // Select component
      expect(find.text('Bánh que Pocky'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Chọn'));
      await tester.pumpAndSettle();

      // Close component sheet using the close button in the modal sheet
      await tester.tap(find.byIcon(Icons.close).last);
      await tester.pumpAndSettle();

      // Verify component added
      expect(find.text('Bánh que Pocky'), findsOneWidget);
      expect(find.textContaining('Giá vốn gợi ý: 8.000 đ'), findsOneWidget);

      // Tap "Áp dụng" suggested cost
      await tester.tap(find.text('Áp dụng'));
      await tester.pumpAndSettle();

      final costField = tester.widget<TextFormField>(
          find.widgetWithText(TextFormField, 'Giá vốn'));
      expect(costField.controller?.text, equals('8000'));
    });

    testWidgets('Allows adding custom attributes (Color, Size)',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          child: const AddProductPage(),
          user: supervisorUser,
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Thêm thuộc tính"
      await tester.tap(find.text('Thêm thuộc tính (Màu sắc, kích thước...)'));
      await tester.pumpAndSettle();

      // Dialog opens
      expect(find.text('Thêm thuộc tính'), findsOneWidget);
      await tester.enterText(
          find.widgetWithText(TextField,
              'Tên thuộc tính (Ví dụ: Màu sắc, Kích thước...)'),
          'Màu sắc');
      await tester.enterText(
          find.widgetWithText(
              TextField, 'Giá trị (Ví dụ: Đỏ, Xanh, L, XL...)'),
          'Đỏ');

      await tester.tap(find.widgetWithText(FilledButton, 'Thêm'));
      await tester.pumpAndSettle();

      // Attribute chip & list item displayed
      expect(find.text('Màu sắc: Đỏ'), findsOneWidget);
      expect(find.text('1 thuộc tính'), findsOneWidget);
    });
  });
}
