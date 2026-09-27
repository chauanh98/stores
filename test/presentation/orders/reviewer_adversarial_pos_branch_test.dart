import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/auth/user_filter_hydration.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';

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

  group('Adversarial Reviewer: POS Branch Scoping and Edge Cases', () {
    testWidgets(
        'Supervisor with role "giamsat" has switch branch enabled and persists selection',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const giamSatUser = UserAccount(
        username: 'giamsat_01',
        displayName: 'Giám sát viên',
        role: 'giamsat',
        storeId: 'store_001',
      );

      const productP1 = Product(
        id: 'p1',
        name: 'Sản phẩm 1',
        code: 'SP1',
        price: 50000,
        costPrice: 30000,
        category: 'Test',
        branchStocks: {'store_001': 10, 'store_002': 25},
      );

      final mockProductRepo = _MockProductRepository([productP1]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(giamSatUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            productRepositoryProvider.overrideWithValue(mockProductRepo),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: POSPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Verify branch switcher button exists and is clickable for supervisor
      final branchButton = find.byKey(const Key('pos_branch_switcher_button'));
      expect(branchButton, findsOneWidget);

      await tester.tap(branchButton);
      await tester.pumpAndSettle();

      expect(find.text('Chọn chi nhánh làm việc'), findsOneWidget);

      // Select Chi nhánh Thới Bình
      await tester.tap(find.text('Chi nhánh Thới Bình'));
      await tester.pumpAndSettle();

      // Check snackbar
      expect(find.text('Đã chuyển sang Chi nhánh Thới Bình'), findsOneWidget);

      // Verify SharedPreferences persisted the selection for giamsat_01
      expect(prefs.getString('selected_store_giamsat_01'), equals('store_002'));
    });

    testWidgets(
        'Tapping the currently active branch in POS selector does not trigger SnackBar',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      const adminUser = UserAccount(
        username: 'admin',
        displayName: 'Quản trị viên',
        role: 'admin',
        storeId: 'store_001',
      );

      final mockProductRepo = _MockProductRepository([]);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            currentStoreIdProvider.overrideWith((ref) => 'store_001'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            productRepositoryProvider.overrideWithValue(mockProductRepo),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: POSPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // Open selector
      await tester.tap(find.byKey(const Key('pos_branch_switcher_button')));
      await tester.pumpAndSettle();

      // Tap the currently active branch in the bottom sheet (Đông Thắng)
      await tester.tap(find.widgetWithText(ListTile, 'Chi nhánh Đông Thắng'));
      await tester.pumpAndSettle();

      // SnackBar should NOT appear because no branch was changed
      expect(find.text('Đã chuyển sang Chi nhánh Đông Thắng'), findsNothing);
    });

    testWidgets(
        'Stock badge is branch-scoped: high stock branch displays "Còn hàng" even if global stock is low',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      // Product has 50 units in store_002, but -48 in store_001. Global stock is 2 <= 5.
      const productIsolated = Product(
        id: 'p_isolated',
        name: 'Đèn trang trí',
        code: 'DTT',
        price: 100000,
        costPrice: 60000,
        category: 'Đèn',
        minStock: 5,
        branchStocks: {
          'store_001': -48,
          'store_002': 50,
        },
      );

      final mockProductRepo = _MockProductRepository([productIsolated]);

      const staffThoiBinh = UserAccount(
        username: 'staff_tb',
        displayName: 'Nhân viên Thới Bình',
        role: 'nhanvien',
        storeId: 'store_002',
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffThoiBinh)),
            currentStoreIdProvider.overrideWith((ref) => 'store_002'),
            availableStoresProvider.overrideWith((ref) async => {
                  'store_001': 'Chi nhánh Đông Thắng',
                  'store_002': 'Chi nhánh Thới Bình',
                }),
            productRepositoryProvider.overrideWithValue(mockProductRepo),
            filterStorageServiceProvider
                .overrideWithValue(FilterStorageService(prefs)),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: POSPage(),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // At store_002, stock is 50 > minStock (5). It MUST show "Còn hàng", NOT "Sắp hết"
      expect(find.text('Còn hàng'), findsOneWidget);
      expect(find.text('Sắp hết'), findsNothing);
      expect(find.text('Hết hàng'), findsNothing);
    });

    test(
        'resetAllInMemoryFilters cleanly invalidates selectedPOSBranchProvider across logins',
        () {
      final container = ProviderContainer(
        overrides: [
          currentStoreIdProvider.overrideWith((ref) => 'store_001'),
        ],
      );
      addTearDown(container.dispose);

      // Initially store_001
      expect(container.read(selectedPOSBranchProvider), equals('store_001'));

      // User switches branch to store_002
      container.read(selectedPOSBranchProvider.notifier).state = 'store_002';
      expect(container.read(selectedPOSBranchProvider), equals('store_002'));

      // Reset in-memory filters (simulates user logout / session clear)
      resetAllInMemoryFilters(container);

      // After invalidate, provider recomputes from currentStoreIdProvider (store_001)
      expect(container.read(selectedPOSBranchProvider), equals('store_001'));
    });
  });
}
