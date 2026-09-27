import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/product_unit.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/inter_store_transfer_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';

class _FakeProductRepository extends Fake implements ProductRepository {
  Product? lastUpsertedProduct;

  @override
  Future<void> upsert(Product product) async {
    lastUpsertedProduct = product;
  }
}

class _FakeInventoryRepository extends Fake implements InventoryRepository {
  final List<InventoryTransaction> recordedTransactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    recordedTransactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(recordedTransactions);
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
      authProvider.overrideWith((ref) =>
          _FakeAuthNotifier(const UserAccount(
            username: 'admin_01',
            displayName: 'Quản trị viên',
            role: 'admin',
            storeId: 'store_001',
          ))),
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      branchesProvider.overrideWithValue(_defaultBranches),
      availableStoresProvider.overrideWith((ref) async =>
      {
        'store_001': 'Chi nhánh Đông Thắng',
        'store_002': 'Chi nhánh Thời Bình',
      }),
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

  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên Thới Bình',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên Hệ thống',
    role: 'admin',
    storeId: 'store_001',
  );

  const supervisorUser = UserAccount(
    username: 'supervisor_01',
    displayName: 'Chủ chuỗi Cửa hàng',
    role: 'supervisor',
    storeId: 'store_001',
  );

  final sampleUnits = [
    const ProductUnit(
      id: 'unit_loc6',
      unitName: 'Lốc (6 lon)',
      conversionRate: 6,
      price: 88000,
      costPrice: 65000,
      barcode: '893111111006',
      code: 'BSG-LOC6',
      isDirectSale: true,
    ),
    const ProductUnit(
      id: 'unit_thung24',
      unitName: 'Thùng (24 lon)',
      conversionRate: 24,
      price: 345000,
      costPrice: 260000,
      barcode: '893111111024',
      code: 'BSG-THUNG24',
      isDirectSale: true,
    ),
  ];

  final sampleProduct = Product(
    id: 'prod_bsg01',
    name: 'Bia Saigon Special 330ml',
    code: 'BSG01',
    barcode: '893111111001',
    brand: 'Sabeco',
    price: 15000,
    costPrice: 11000,
    branchStocks: const {'branch_1': 50, 'branch_2': 30},
    category: 'Đồ uống',
    category3Levels: 'Bách hóa >> Đồ uống >> Bia & Rượu',
    unit: 'Lon',
    description: 'Bia Saigon Special lon cao 330ml 100% lúa mạch',
    minStock: 10,
    maxStock: 200,
    units: sampleUnits,
  );

  const sampleComboProduct = Product(
    id: 'prod_combo01',
    name: 'Combo Tiệc Vui',
    code: 'CB01',
    barcode: '893999999001',
    brand: 'Stores Combo',
    price: 95000,
    costPrice: 70000,
    branchStocks: {'branch_1': 10, 'branch_2': 5},
    category: 'Combo',
    unit: 'Gói',
    isCombo: true,
    comboComponents: [
      ComboComponent(
        productId: 'prod_bsg01',
        productCode: 'BSG01',
        productName: 'Bia Saigon Special 330ml',
        quantity: 4,
        costPrice: 11000,
      ),
    ],
  );

  final sampleTransactions = [
    InventoryTransaction(
      id: 'tx_import_01',
      productId: 'prod_bsg01',
      type: TransactionType.import,
      quantity: 50,
      date: DateTime(2026, 8, 15, 10, 30),
      note: 'Nhập lô hàng Sabeco tháng 8',
      importPrice: 11000,
      createdBy: 'supervisor_01',
      createdByName: 'Chủ chuỗi Cửa hàng',
    ),
    InventoryTransaction(
      id: 'tx_export_01',
      productId: 'prod_bsg01',
      type: TransactionType.export,
      quantity: 12,
      date: DateTime(2026, 8, 15, 14, 15),
      note: 'HD-20260815-001',
      createdBy: 'staff_01',
      createdByName: 'Nhân viên Thới Bình',
    ),
    InventoryTransaction(
      id: 'tx_transfer_01',
      productId: 'prod_bsg01',
      type: TransactionType.export,
      quantity: 20,
      date: DateTime(2026, 8, 16, 9, 0),
      note: 'Chuyển kho từ Chi nhánh Đông Thắng sang Thời Bình',
      createdBy: 'supervisor_01',
      createdByName: 'Chủ chuỗi Cửa hàng',
    ),
    InventoryTransaction(
      id: 'tx_audit_01',
      productId: 'prod_bsg01',
      type: TransactionType.inventoryAudit,
      quantity: 8,
      date: DateTime(2026, 8, 16, 11, 0),
      note:
      'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 18, chênh lệch: +8)',
      importPrice: 11000,
      createdBy: 'supervisor_01',
      createdByName: 'Chủ chuỗi Cửa hàng',
    ),
  ];

  group('Milestone 4: Product Information Card & Converted Units Display', () {
    testWidgets(
        'Renders all product details (SKU, barcode, brand, category, base unit, image)',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value(sampleTransactions)),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Product Header
          expect(find.text('Bia Saigon Special 330ml'), findsWidgets);
          expect(find.text('Còn hàng (80)'), findsOneWidget);

          // Basic info card rows
          expect(find.text('Mã hàng'), findsOneWidget);
          expect(find.text('BSG01'), findsWidgets);
          expect(find.text('Mã vạch'), findsWidgets);
          expect(find.text('893111111001'), findsOneWidget);
          expect(find.text('Thương hiệu'), findsOneWidget);
          expect(find.text('Sabeco'), findsWidgets);
          expect(find.text('Nhóm hàng'), findsOneWidget);
          expect(
              find.text('Bách hóa >> Đồ uống >> Bia & Rượu'), findsOneWidget);
          expect(find.text('Đơn vị cơ bản'), findsOneWidget);
          expect(find.text('Lon'), findsOneWidget);
          expect(find.text('Giá bán'), findsOneWidget);
          expect(find.text('15.000 đ'), findsOneWidget);

          // Converted Units Table
          expect(find.text('Đơn vị tính quy đổi'), findsOneWidget);
          expect(find.text('2 đơn vị'), findsOneWidget);
          expect(find.text('Lốc (6 lon)'), findsOneWidget);
          expect(find.text('1 Lốc (6 lon) = 6 Lon'), findsOneWidget);
          expect(find.text('88.000 đ'), findsOneWidget);
          expect(find.text('Thùng (24 lon)'), findsOneWidget);
          expect(find.text('1 Thùng (24 lon) = 24 Lon'), findsOneWidget);
          expect(find.text('345.000 đ'), findsOneWidget);
        });

    testWidgets('Renders combo components card when product is combo',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: const ProductDetailPage(product: sampleComboProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) =>
                    Stream.value([sampleProduct, sampleComboProduct])),
                transactionsByProductProvider(sampleComboProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('COMBO'), findsOneWidget);
          expect(find.text('Thành phần trong Combo'), findsOneWidget);
          expect(find.text('1 món'), findsOneWidget);
          expect(find.text('x4'), findsOneWidget);
          expect(find.text('Bia Saigon Special 330ml'), findsOneWidget);
        });
  });

  group('Milestone 4: Cost Price Security & Dynamic Eye Toggle', () {
    testWidgets('Staff: Cost price is strictly HIDDEN everywhere',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider.overrideWith((ref) =>
                    _FakeAuthNotifier(staffUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value(sampleTransactions)),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // In Basic Info Card: No 'Giá vốn' row
          expect(find.text('Giá vốn'), findsNothing);
          expect(find.text('11.000 đ'), findsNothing);

          // Eye toggle icon is NOT present for Staff
          expect(find.byIcon(Icons.visibility_outlined), findsNothing);
          expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);

          // In Converted units: No cost prices
          expect(find.textContaining('Vốn:'), findsNothing);

          // In Stock card history: Import price is hidden
          expect(find.textContaining('Giá nhập:'), findsNothing);
        });

    testWidgets(
        'Admin: Cost price is VISIBLE and has interactive eye toggle (canViewCostPrice is true)',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider.overrideWith((ref) =>
                    _FakeAuthNotifier(adminUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value(sampleTransactions)),
              ],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Giá vốn'), findsOneWidget);
          expect(find.text('••••••'), findsWidgets);
          expect(find.text('11.000 đ'), findsNothing);

          // Toggle eye button to show prices
          final eyeButton = find.byTooltip('Ẩn / Hiện giá vốn');
          expect(eyeButton, findsOneWidget);

          await tester.tap(eyeButton);
          await tester.pumpAndSettle();

          // Now cost price is revealed!
          expect(find.text('11.000 đ'), findsWidgets);
          expect(find.text('Vốn: 65.000 đ'), findsOneWidget);
          expect(find.text('Vốn: 260.000 đ'), findsOneWidget);
        });

    testWidgets(
        'Supervisor: Cost price has interactive eye toggle to reveal / mask prices',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value(sampleTransactions)),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Supervisor sees 'Giá vốn' row
          expect(find.text('Giá vốn'), findsOneWidget);

          // Initially showCostPriceProvider is false -> displays masked '••••••'
          expect(find.text('••••••'), findsWidgets);
          expect(find.text('11.000 đ'), findsNothing);

          // Toggle eye button to show prices
          final eyeButton = find.byTooltip('Ẩn / Hiện giá vốn');
          expect(eyeButton, findsOneWidget);

          await tester.tap(eyeButton);
          await tester.pumpAndSettle();

          // Now cost price is revealed!
          expect(find.text('11.000 đ'), findsWidgets);
          expect(find.text('Vốn: 65.000 đ'), findsOneWidget); // Unit 1 cost
          expect(find.text('Vốn: 260.000 đ'), findsOneWidget); // Unit 2 cost
          expect(find.text('Giá nhập: 11.000 đ'),
              findsOneWidget); // Transaction import price

          // Toggle eye button again to hide prices
          await tester.tap(eyeButton);
          await tester.pumpAndSettle();

          // Prices are masked again
          expect(find.text('••••••'), findsWidgets);
          expect(find.text('Vốn: ••••••'), findsNWidgets(2));
          expect(find.text('Giá nhập: ••••••'), findsOneWidget);
        });
  });

  group('Milestone 4: Inline Branch Stock Allocation Table', () {
    testWidgets('Displays breakdown for all branches and total inventory count',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Table Header & Title
          expect(find.text('Phân bổ tồn kho theo chi nhánh'), findsOneWidget);
          expect(find.text('Tổng: 80'), findsOneWidget);

          // Branch allocations
          expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
          expect(find.text('50'), findsOneWidget);
          expect(find.text('Chi nhánh Thời Bình'), findsOneWidget);
          expect(find.text('30'), findsOneWidget);

          // Total row
          expect(find.text('Tổng tồn toàn chuỗi'), findsOneWidget);
          expect(find.text('80'), findsWidgets);
        });
  });

  group('Milestone 4: Interactive Stock Card History & 4 Filter Tabs', () {
    testWidgets(
        'Renders 4 filter tabs and filters transactions chronologically',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value(sampleTransactions)),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Stock Card Header & 5 Tabs
          expect(find.text('Lịch sử thẻ kho'), findsOneWidget);
          expect(find.text('Tất cả'), findsOneWidget);
          expect(find.text('Nhập hàng'), findsWidgets);
          expect(find.text('Bán hàng / Xuất'), findsWidgets);
          expect(find.text('Chuyển kho'), findsWidgets);
          expect(find.text('Cân bằng kho'), findsWidgets);

          // Initial: Tab 'Tất cả' shows all 4 transactions
          expect(find.text('Nhập lô hàng Sabeco tháng 8'), findsOneWidget);
          expect(
              find.text('Bán hàng (Mã đơn: HD-20260815-001)'), findsOneWidget);
          expect(
              find.text('Chuyển kho từ Chi nhánh Đông Thắng sang Thời Bình'),
              findsOneWidget);
          expect(
              find.text(
                  'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 18, chênh lệch: +8)'),
              findsOneWidget);
          expect(find.text('+50'), findsOneWidget);
          expect(find.text('-12'), findsOneWidget);
          expect(find.text('-20'), findsOneWidget);
          expect(find.text('+8'), findsOneWidget);

          // 1. Filter: 'Nhập hàng' (tap Segment in SegmentedButton)
          final importTab = find.descendant(
            of: find.byType(SegmentedButton<int>),
            matching: find.text('Nhập hàng'),
          );
          await tester.tap(importTab);
          await tester.pumpAndSettle();

          expect(find.text('Nhập lô hàng Sabeco tháng 8'), findsOneWidget);
          expect(find.text('Bán hàng (Mã đơn: HD-20260815-001)'), findsNothing);
          expect(
              find.text('Chuyển kho từ Chi nhánh Đông Thắng sang Thời Bình'),
              findsNothing);
          expect(
              find.text(
                  'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 18, chênh lệch: +8)'),
              findsNothing);

          // 2. Filter: 'Bán hàng / Xuất' (tap Segment in SegmentedButton)
          final exportTab = find.descendant(
            of: find.byType(SegmentedButton<int>),
            matching: find.text('Bán hàng / Xuất'),
          );
          await tester.tap(exportTab);
          await tester.pumpAndSettle();

          expect(
              find.text('Bán hàng (Mã đơn: HD-20260815-001)'), findsOneWidget);
          expect(find.text('Nhập lô hàng Sabeco tháng 8'), findsNothing);
          expect(
              find.text('Chuyển kho từ Chi nhánh Đông Thắng sang Thời Bình'),
              findsNothing);
          expect(
              find.text(
                  'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 18, chênh lệch: +8)'),
              findsNothing);

          // 3. Filter: 'Chuyển kho' (tap Segment in SegmentedButton)
          final transferTab = find.descendant(
            of: find.byType(SegmentedButton<int>),
            matching: find.text('Chuyển kho'),
          );
          await tester.tap(transferTab);
          await tester.pumpAndSettle();

          expect(
              find.text('Chuyển kho từ Chi nhánh Đông Thắng sang Thời Bình'),
              findsOneWidget);
          expect(find.text('Nhập lô hàng Sabeco tháng 8'), findsNothing);
          expect(find.text('Bán hàng (Mã đơn: HD-20260815-001)'), findsNothing);
          expect(
              find.text(
                  'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 18, chênh lệch: +8)'),
              findsNothing);

          // 4. Filter: 'Cân bằng kho' (tap Segment in SegmentedButton)
          final auditTab = find.descendant(
            of: find.byType(SegmentedButton<int>),
            matching: find.text('Cân bằng kho'),
          );
          await tester.tap(auditTab);
          await tester.pumpAndSettle();

          expect(
              find.text(
                  'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 18, chênh lệch: +8)'),
              findsOneWidget);
          expect(find.text('+8'), findsOneWidget);
          expect(find.text('Nhập lô hàng Sabeco tháng 8'), findsNothing);
          expect(find.text('Bán hàng (Mã đơn: HD-20260815-001)'), findsNothing);
          expect(
              find.text('Chuyển kho từ Chi nhánh Đông Thắng sang Thời Bình'),
              findsNothing);

          // 5. Return to 'Tất cả'
          final allTab = find.descendant(
            of: find.byType(SegmentedButton<int>),
            matching: find.text('Tất cả'),
          );
          await tester.tap(allTab);
          await tester.pumpAndSettle();

          expect(find.text('Nhập lô hàng Sabeco tháng 8'), findsOneWidget);
          expect(
              find.text('Bán hàng (Mã đơn: HD-20260815-001)'), findsOneWidget);
          expect(
              find.text(
                  'Cân bằng kho trực tiếp (Tồn cũ: 10 -> Tồn mới: 18, chênh lệch: +8)'),
              findsOneWidget);
        });

    testWidgets('Displays empty state message when product has no transactions',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Chưa có lịch sử giao dịch'), findsOneWidget);
        });
  });

  group('Milestone 4: Quick Action Shortcuts Bar & Barcode Print Dialog', () {
    testWidgets('Quick action shortcuts bar renders all 4 buttons',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          expect(find.text('Nhập hàng'), findsWidgets);
          expect(find.text('Chuyển kho'), findsWidgets);
          expect(find.text('Chỉnh sửa'), findsOneWidget);
          expect(find.text('In mã vạch'), findsOneWidget);
        });

    testWidgets('Tapping [Nhập hàng] navigates to ImportInventoryPage',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Tap [Nhập hàng] quick button (using icon or first text)
          await tester.tap(find.byIcon(Icons.input_rounded));
          await tester.pumpAndSettle();

          expect(find.byType(ImportInventoryPage), findsOneWidget);
        });

    testWidgets('Tapping [Chuyển kho] navigates to InterStoreTransferPage',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Tap [Chuyển kho] quick button
          await tester.tap(find.byIcon(Icons.swap_horiz_rounded));
          await tester.pumpAndSettle();

          expect(find.byType(InterStoreTransferPage), findsOneWidget);
        });

    testWidgets('Tapping [In mã vạch] opens barcode print modal dialog',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Tap [In mã vạch] button
          await tester.tap(find.byIcon(Icons.qr_code_2_rounded));
          await tester.pumpAndSettle();

          // Dialog is displayed
          expect(find.text('Mã vạch sản phẩm'), findsOneWidget);
          expect(find.text('Bia Saigon Special 330ml'), findsWidgets);
          expect(find.text('Mã SKU: BSG01'), findsOneWidget);
          expect(find.text('893111111001'), findsWidgets);
          expect(find.text('Sao chép mã'), findsOneWidget);
          expect(find.text('In mã vạch'), findsWidgets);
          expect(find.text('Đóng'), findsOneWidget);

          // Tap 'Sao chép mã'
          await tester.tap(find.text('Sao chép mã'));
          await tester.pumpAndSettle();
          expect(
              find.text('Đã sao chép mã vạch: 893111111001'), findsOneWidget);

          // Tap 'In mã vạch' in dialog to trigger action and dismiss
          await tester.tap(find.byIcon(Icons.print_rounded));
          await tester.pumpAndSettle();

          expect(
              find.text(
                  'Đang gửi lệnh in mã vạch cho sản phẩm Bia Saigon Special 330ml...'),
              findsOneWidget);
        });

    testWidgets('Staff: Tapping [Chỉnh sửa] shows permission denied SnackBar',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider.overrideWith((ref) =>
                    _FakeAuthNotifier(staffUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Staff taps [Chỉnh sửa]
          await tester.tap(find.byIcon(Icons.edit_outlined));
          await tester.pumpAndSettle();

          expect(find.text('Bạn không có quyền chỉnh sửa sản phẩm'),
              findsOneWidget);
        });

    testWidgets('Admin/Supervisor: Tapping [Chỉnh sửa] enters Edit Form mode',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Supervisor taps [Chỉnh sửa]
          await tester.tap(find.byIcon(Icons.edit_outlined));
          await tester.pumpAndSettle();

          // AppBar title changes to 'Thông tin cơ bản' (Edit mode)
          expect(find.text('Thông tin cơ bản'), findsOneWidget);
          expect(find.text('Lưu'), findsOneWidget);
          expect(find.byIcon(Icons.close), findsOneWidget);
        });

    testWidgets(
        'Direct Stock Edit: Modifying stock directly auto-generates InventoryTransaction (inventoryAudit)',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final fakeProductRepo = _FakeProductRepository();
          final fakeInventoryRepo = _FakeInventoryRepository();

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(supervisorUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                productRepositoryProvider
                    .overrideWithValue(fakeProductRepo),
                inventoryRepositoryProvider
                    .overrideWithValue(fakeInventoryRepo),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Supervisor taps [Sửa] text button
          await tester.tap(find.text('Sửa'));
          await tester.pumpAndSettle();

          // Find stock TextField in edit form (contains '50' initially)
          final stockField = find.widgetWithText(TextField, '50');
          expect(stockField, findsOneWidget);

          // Enter new stock '58' (+8)
          await tester.enterText(stockField, '58');
          await tester.pumpAndSettle();

          // Tap 'Lưu'
          await tester.tap(find.text('Lưu'));
          await tester.pumpAndSettle();

          // Verify product was updated with branch_1: 58
          expect(fakeProductRepo.lastUpsertedProduct, isNotNull);
          expect(fakeProductRepo.lastUpsertedProduct!.stockInBranch('branch_1'),
              equals(58));

          // Verify InventoryTransaction was recorded
          expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
          final tx = fakeInventoryRepo.recordedTransactions.first;
          expect(tx.productId, equals(sampleProduct.id));
          expect(tx.type, equals(TransactionType.inventoryAudit));
          expect(tx.quantity, equals(8));
          expect(
              tx.note, contains('Tồn cũ: 50 -> Tồn mới: 58, chênh lệch: +8'));
          expect(tx.importPrice, equals(sampleProduct.costPrice));
          expect(tx.createdBy, equals(supervisorUser.username));
          expect(tx.createdByName, equals(supervisorUser.name));
          expect(tx.storeId, equals('store_001'));
          expect(tx.isAuditNegative, equals(false));
          expect(tx.auditDifference, equals(8));
        });

    testWidgets(
        'Direct Stock Edit: Decreasing stock directly auto-generates negative InventoryTransaction',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final fakeProductRepo = _FakeProductRepository();
          final fakeInventoryRepo = _FakeInventoryRepository();

          await tester.pumpWidget(
            _buildTestApp(
              child: ProductDetailPage(product: sampleProduct),
              overrides: [
                authProvider
                    .overrideWith((ref) => _FakeAuthNotifier(adminUser)),
                productListProvider
                    .overrideWith((ref) => Stream.value([sampleProduct])),
                productRepositoryProvider
                    .overrideWithValue(fakeProductRepo),
                inventoryRepositoryProvider
                    .overrideWithValue(fakeInventoryRepo),
                transactionsByProductProvider(sampleProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          // Admin taps [Sửa] text button
          await tester.tap(find.text('Sửa'));
          await tester.pumpAndSettle();

          final stockField = find.widgetWithText(TextField, '50');
          expect(stockField, findsOneWidget);

          // Decrease stock to '45' (-5)
          await tester.enterText(stockField, '45');
          await tester.pumpAndSettle();

          // Tap 'Lưu'
          await tester.tap(find.text('Lưu'));
          await tester.pumpAndSettle();

          // Verify product updated with branch_1: 45
          expect(fakeProductRepo.lastUpsertedProduct, isNotNull);
          expect(fakeProductRepo.lastUpsertedProduct!.stockInBranch('branch_1'),
              equals(45));

          // Verify negative InventoryTransaction
          expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
          final tx = fakeInventoryRepo.recordedTransactions.first;
          expect(tx.productId, equals(sampleProduct.id));
          expect(tx.type, equals(TransactionType.inventoryAudit));
          expect(tx.quantity, equals(5));
          expect(
              tx.note, contains('Tồn cũ: 50 -> Tồn mới: 45, chênh lệch: -5'));
          expect(tx.createdBy, equals(adminUser.username));
          expect(tx.createdByName, equals(adminUser.name));
          expect(tx.storeId, equals('store_001'));
          expect(tx.isAuditNegative, equals(true));
          expect(tx.auditDifference, equals(-5));
        });
  });

  group('Milestone 2 (F4, F5, F6): Store-Scoped Stock Mutation & Pre-fill', () {
    const canonicalProduct = Product(
      id: 'prod_m2_01',
      name: 'Bia Saigon Special 330ml',
      code: 'BSG01',
      barcode: '893111111001',
      price: 15000,
      costPrice: 11000,
      branchStocks: {'store_001': 50, 'store_002': 30},
      // Total: 80
      category: 'Đồ uống',
    );

    // ---------------------------------------------------------------------------
    // F4: Active Store Form Pre-fill Tests
    // ---------------------------------------------------------------------------
    testWidgets(
        'F4: Pre-fills Store 1 stock (50) when currentStoreId is store_001',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: const ProductDetailPage(product: canonicalProduct),
              overrides: [
                currentStoreIdProvider.overrideWith((ref) => 'store_001'),
                productListProvider
                    .overrideWith((ref) => Stream.value([canonicalProduct])),
                transactionsByProductProvider(canonicalProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Sửa'));
          await tester.pumpAndSettle();

          final stockField = find.widgetWithText(TextField, '50');
          expect(stockField, findsOneWidget);
        });

    testWidgets(
        'F4: Pre-fills Store 2 stock (30) when currentStoreId is store_002',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: const ProductDetailPage(product: canonicalProduct),
              overrides: [
                currentStoreIdProvider.overrideWith((ref) => 'store_002'),
                productListProvider
                    .overrideWith((ref) => Stream.value([canonicalProduct])),
                transactionsByProductProvider(canonicalProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Sửa'));
          await tester.pumpAndSettle();

          final stockField = find.widgetWithText(TextField, '30');
          expect(stockField, findsOneWidget);
        });

    testWidgets('F4: Cancel edit reverts pre-filled controller value',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: const ProductDetailPage(product: canonicalProduct),
              overrides: [
                currentStoreIdProvider.overrideWith((ref) => 'store_001'),
                productListProvider
                    .overrideWith((ref) => Stream.value([canonicalProduct])),
                transactionsByProductProvider(canonicalProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Sửa'));
          await tester.pumpAndSettle();

          final stockField = find.widgetWithText(TextField, '50');
          await tester.enterText(stockField, '999');
          await tester.pumpAndSettle();

          // Tap close/cancel button
          await tester.tap(find.byIcon(Icons.close));
          await tester.pumpAndSettle();

          // Re-enter edit mode
          await tester.tap(find.text('Sửa'));
          await tester.pumpAndSettle();

          expect(find.widgetWithText(TextField, '50'), findsOneWidget);
          expect(find.widgetWithText(TextField, '999'), findsNothing);
        });

    // ---------------------------------------------------------------------------
    // F5: Dynamic Field Label with Active Store Name
    // ---------------------------------------------------------------------------
    testWidgets(
        'F5: Displays dynamic field label with Chi nhánh Đông Thắng for store_001',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: const ProductDetailPage(product: canonicalProduct),
              overrides: [
                currentStoreIdProvider.overrideWith((ref) => 'store_001'),
                availableStoresProvider.overrideWith((ref) async =>
                {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
                productListProvider
                    .overrideWith((ref) => Stream.value([canonicalProduct])),
                transactionsByProductProvider(canonicalProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Sửa'));
          await tester.pumpAndSettle();

          expect(
              find.text('Số lượng tồn kho (Chi nhánh Đông Thắng)'),
              findsOneWidget);
        });

    testWidgets(
        'F5: Displays dynamic field label with Chi nhánh Thới Bình for store_002',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          await tester.pumpWidget(
            _buildTestApp(
              child: const ProductDetailPage(product: canonicalProduct),
              overrides: [
                currentStoreIdProvider.overrideWith((ref) => 'store_002'),
                availableStoresProvider.overrideWith((ref) async =>
                {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
                productListProvider
                    .overrideWith((ref) => Stream.value([canonicalProduct])),
                transactionsByProductProvider(canonicalProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Sửa'));
          await tester.pumpAndSettle();

          expect(
              find.text('Số lượng tồn kho (Chi nhánh Thới Bình)'),
              findsOneWidget);
        });

    // ---------------------------------------------------------------------------
    // F6: Scoped Mutation, Cross-Store Isolation & Recalculation
    // ---------------------------------------------------------------------------
    testWidgets(
        'F6: Positive stock mutation (+8) in store_001 updates store_001, preserves store_002, recalculates aggregate stock, and records audit',
            (tester) async {
          tester.view.physicalSize = const Size(1000, 2400);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);

          final fakeProductRepo = _FakeProductRepository();
          final fakeInventoryRepo = _FakeInventoryRepository();

          await tester.pumpWidget(
            _buildTestApp(
              child: const ProductDetailPage(product: canonicalProduct),
              overrides: [
                currentStoreIdProvider.overrideWith((ref) => 'store_001'),
                productRepositoryProvider.overrideWithValue(fakeProductRepo),
                inventoryRepositoryProvider.overrideWithValue(
                    fakeInventoryRepo),
                productListProvider
                    .overrideWith((ref) => Stream.value([canonicalProduct])),
                transactionsByProductProvider(canonicalProduct.id)
                    .overrideWith((ref) => Stream.value([])),
              ],
            ),
          );
          await tester.pumpAndSettle();

          await tester.tap(find.text('Sửa'));
          await tester.pumpAndSettle();

          final stockField = find.widgetWithText(TextField, '50');
          await tester.enterText(stockField, '58');
          await tester.pumpAndSettle();

          await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // 1. Verify Product Isolation and Recalculation
      final updated = fakeProductRepo.lastUpsertedProduct!;
      expect(updated.branchStocks['store_001'], equals(58));
      expect(updated.branchStocks['store_002'], equals(30)); // store_002 untouched
      expect(updated.stock, equals(88)); // 58 + 30 = 88

      // 2. Verify Structured Audit Transaction
      expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
      final tx = fakeInventoryRepo.recordedTransactions.first;
      expect(tx.productId, equals(canonicalProduct.id));
      expect(tx.type, equals(TransactionType.inventoryAudit));
      expect(tx.quantity, equals(8));
      expect(tx.importPrice, equals(canonicalProduct.costPrice));
      expect(tx.storeId, equals('store_001'));
      expect(tx.isAuditNegative, equals(false));
      expect(tx.auditDifference, equals(8));
      expect(tx.note, contains('Tồn cũ: 50 -> Tồn mới: 58, chênh lệch: +8'));
    });

    testWidgets(
        'F6: Negative stock mutation (-10) in store_002 updates store_002, preserves store_001, recalculates aggregate stock, and records audit',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeProductRepo = _FakeProductRepository();
      final fakeInventoryRepo = _FakeInventoryRepository();

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductDetailPage(product: canonicalProduct),
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            productRepositoryProvider.overrideWithValue(fakeProductRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            productListProvider
                .overrideWith((ref) => Stream.value([canonicalProduct])),
            transactionsByProductProvider(canonicalProduct.id)
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      final stockField = find.widgetWithText(TextField, '30');
      await tester.enterText(stockField, '20');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // 1. Verify Product Isolation and Recalculation
      final updated = fakeProductRepo.lastUpsertedProduct!;
      expect(updated.branchStocks['store_002'], equals(20));
      expect(updated.branchStocks['store_001'], equals(50)); // store_001 untouched
      expect(updated.stock, equals(70)); // 50 + 20 = 70

      // 2. Verify Structured Audit Transaction
      expect(fakeInventoryRepo.recordedTransactions.length, equals(1));
      final tx = fakeInventoryRepo.recordedTransactions.first;
      expect(tx.productId, equals(canonicalProduct.id));
      expect(tx.type, equals(TransactionType.inventoryAudit));
      expect(tx.quantity, equals(10));
      expect(tx.storeId, equals('store_002'));
      expect(tx.isAuditNegative, equals(true));
      expect(tx.auditDifference, equals(-10));
      expect(tx.note, contains('Tồn cũ: 30 -> Tồn mới: 20, chênh lệch: -10'));
    });

    testWidgets(
        'F6: Direct stock update cleans up legacy branch_1/branch_2 keys on save',
        (tester) async {
      tester.view.physicalSize = const Size(1000, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final fakeProductRepo = _FakeProductRepository();
      final fakeInventoryRepo = _FakeInventoryRepository();

      const legacyProduct = Product(
        id: 'prod_legacy_01',
        name: 'Legacy Product',
        code: 'LEG01',
        price: 20000,
        costPrice: 15000,
        branchStocks: {'branch_1': 40, 'branch_2': 25},
        category: 'Đồ uống',
      );

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductDetailPage(product: legacyProduct),
          overrides: [
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            productRepositoryProvider.overrideWithValue(fakeProductRepo),
            inventoryRepositoryProvider.overrideWithValue(fakeInventoryRepo),
            productListProvider
                .overrideWith((ref) => Stream.value([legacyProduct])),
            transactionsByProductProvider(legacyProduct.id)
                .overrideWith((ref) => Stream.value([])),
          ],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      final stockField = find.widgetWithText(TextField, '40');
      await tester.enterText(stockField, '45');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      final updated = fakeProductRepo.lastUpsertedProduct!;
      expect(updated.stockInBranch('store_001'), equals(45));
      expect(updated.branchStocks['branch_2'], equals(25));
      expect(updated.stock, equals(70));
    });
  });
}
