import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';

class _FakeProductRepository extends Fake implements ProductRepository {
  @override
  Future<void> upsert(Product product) async {}
}

class _FakeInventoryRepository extends Fake implements InventoryRepository {
  @override
  Future<void> record(InventoryTransaction tx) async {}

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

final _defaultBranches = [
  const Branch('branch_1', 'Chi nhánh Đông Thắng'),
  const Branch('branch_2', 'Chi nhánh Thới Bình'),
];

Widget _buildTestApp({
  required Widget child,
}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(const UserAccount(
            username: 'admin_01',
            displayName: 'Quản trị viên',
            role: 'admin',
            storeId: 'store_001',
          ))),
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      branchesProvider.overrideWithValue(_defaultBranches),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': 'Chi nhánh Đông Thắng',
            'store_002': 'Chi nhánh Thới Bình',
          }),
      productRepositoryProvider.overrideWithValue(_FakeProductRepository()),
      inventoryRepositoryProvider.overrideWithValue(_FakeInventoryRepository()),
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

  const longCategoryProduct = Product(
    id: 'prod_long_cat',
    name: 'Nước Ngọt Coca Cola Có Ga Vị Nguyên Bản Chai Nhôm Đặc Biệt',
    code: 'SP-LONG-CAT-99999',
    barcode: '8930000000099999',
    brand: 'Thương hiệu Siêu Dài Quốc Tế Beverage Corporation',
    price: 150000,
    costPrice: 120000,
    branchStocks: {'branch_1': 50, 'branch_2': 30},
    category: 'Bia, Rượu, Nước giải khát >> Nước ngọt có ga >> Lon 330ml nhập khẩu',
    category3Levels:
        'Bia, Rượu, Nước giải khát >> Nước ngọt có ga >> Lon 330ml nhập khẩu',
    unit: 'Thùng 24 lon tiêu chuẩn',
  );

  final testWidths = [320.0, 360.0, 390.0, 412.0];

  for (final width in testWidths) {
    testWidgets(
        'ProductDetailPage has 0 RenderFlex overflow with long category on ${width.toInt()}px width screen',
        (tester) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Track Flutter overflow errors
      final errors = <FlutterErrorDetails>[];
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (FlutterErrorDetails details) {
        errors.add(details);
        originalOnError?.call(details);
      };
      addTearDown(() {
        FlutterError.onError = originalOnError;
      });

      await tester.pumpWidget(
        _buildTestApp(
          child: const ProductDetailPage(product: longCategoryProduct),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ProductDetailPage), findsOneWidget);
      expect(find.text('Nhóm hàng'), findsOneWidget);

      // Check no RenderFlex overflow
      final overflowErrors = errors.where((e) =>
          e.toString().contains('A RenderFlex overflowed') ||
          e.toString().contains('overflowed by'));
      expect(overflowErrors, isEmpty,
          reason:
              'Expected 0 RenderFlex overflow on ${width.toInt()}px width screen');
    });
  }
}
