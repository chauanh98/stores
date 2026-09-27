import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/stock_in_receipts_page.dart';

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

class _FakeSupplierListNotifier extends SupplierListNotifier {
  final List<Supplier> _suppliers;
  _FakeSupplierListNotifier([this._suppliers = const []]);

  @override
  Future<List<Supplier>> build() async => _suppliers;
}

Widget _buildTestApp({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: overrides,
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

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  final commonOverrides = [
    authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': 'Chi nhánh Đông Thắng',
          'store_002': 'Chi nhánh Thới Bình',
        }),
    currentStoreIdProvider.overrideWith((ref) => 'store_001'),
    productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
    rawImportTransactionsStreamProvider
        .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
    allSupplierDebtTransactionsProvider
        .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
    supplierListNotifierProvider.overrideWith(
        () => _FakeSupplierListNotifier([])),
  ];

  group('StockInReceiptsPage - Adversarial & Stress Testing', () {
    testWidgets(
        'ADVERSARIAL: Excel import button is absent on mobile StockInReceiptsPage',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Excel import button is not present on mobile
      expect(
        find.byKey(const Key('stock_in_receipts_import_excel_button')),
        findsNothing,
      );
      expect(find.byTooltip('Nhập Excel'), findsNothing);
      expect(find.byIcon(Icons.upload_file), findsNothing);
    });

    testWidgets(
        'ADVERSARIAL: FAB navigation to ImportInventoryPage safely invalidates rawImportTransactionsStreamProvider on return',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      int invalidateCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          observers: [
            _InvalidationObserver(
              targetProvider: rawImportTransactionsStreamProvider,
              onInvalidated: () {
                invalidateCount++;
              },
            ),
          ],
          overrides: [
            ...commonOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => const AsyncValue.data([]),
            ),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: StockInReceiptsPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Eagerly read so Riverpod initializes the provider element
      final container =
          ProviderScope.containerOf(tester.element(find.byType(StockInReceiptsPage)));
      container.read(rawImportTransactionsStreamProvider);

      final initialInvalidateCount = invalidateCount;

      // Verify FAB presence and text
      expect(find.text('Tạo phiếu nhập'), findsOneWidget);
      expect(find.text('Tạo phiếu nhập mới'), findsNothing);

      // Tap FAB to navigate to ImportInventoryPage
      await tester.tap(find.text('Tạo phiếu nhập'));
      await tester.pumpAndSettle();

      // We are on ImportInventoryPage
      expect(find.byType(ImportInventoryPage), findsOneWidget);

      // Now simulate popping ImportInventoryPage
      final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
      navigator.pop();
      await tester.pumpAndSettle();

      // Back on StockInReceiptsPage
      expect(find.byType(StockInReceiptsPage), findsOneWidget);
      // Verify rawImportTransactionsStreamProvider was invalidated
      expect(invalidateCount, greaterThan(initialInvalidateCount));
      expect(tester.takeException(), isNull);
    });
  });
}

class _InvalidationObserver extends ProviderObserver {
  final ProviderBase targetProvider;
  final VoidCallback onInvalidated;

  _InvalidationObserver({
    required this.targetProvider,
    required this.onInvalidated,
  });

  @override
  void didDisposeProvider(ProviderBase provider, ProviderContainer container) {
    if (provider == targetProvider) {
      onInvalidated();
    }
  }

  @override
  void didUpdateProvider(
    ProviderBase provider,
    Object? previousValue,
    Object? newValue,
    ProviderContainer container,
  ) {
    if (provider == targetProvider) {
      onInvalidated();
    }
  }
}
