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
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/widgets/sample_image_picker_dialog.dart';

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
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
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

class _MockHttpClientResponse extends Stream<List<int>> implements HttpClientResponse {
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

class _FakeAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _MockProductRepository implements ProductRepository {
  List<Product> products = [];
  Product? lastUpserted;

  _MockProductRepository(this.products);

  @override
  Future<void> delete(String id) async {
    products.removeWhere((p) => p.id == id);
  }

  @override
  Future<List<Product>> fetchAll() async => products;

  @override
  Future<Product?> fetchById(String id) async =>
      products.cast<Product?>().firstWhere((p) => p?.id == id, orElse: () => null);

  @override
  Future<void> updateStock(String id, int newStock) async {}

  @override
  Future<void> upsert(Product product) async {
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

  const adminUser = UserAccount(
    username: 'admin_01',
    displayName: 'Quản lý',
    role: 'admin',
    storeId: 'store_001',
  );

  const staffUser = UserAccount(
    username: 'staff_01',
    displayName: 'Nhân viên',
    role: 'nhanvien',
    storeId: 'store_001',
  );

  const sampleProductActive = Product(
    id: 'prod_01',
    name: 'Nước ngọt Coca Cola 330ml',
    code: 'COCA330',
    price: 10000,
    costPrice: 7000,
    branchStocks: {'branch_1': 20, 'branch_2': 10},
    category: 'Đồ uống',
    allowSale: true,
  );

  const sampleProductDisabled = Product(
    id: 'prod_02',
    name: 'Bia Hết Hạn Ngừng Bán',
    code: 'BIA999',
    price: 15000,
    costPrice: 10000,
    branchStocks: {'branch_1': 5, 'branch_2': 0},
    category: 'Đồ uống',
    allowSale: false,
  );

  group('Milestone 2: SampleImagePickerDialog UI Tests', () {
    testWidgets('SampleImagePickerDialog shows smart suggestions and allows selection',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? selectedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () async {
                  selectedUrl = await SampleImagePickerDialog.show(
                    ctx,
                    productName: 'Bàn ăn 6 ghế mặt đá',
                    category: 'Phòng ăn & Bếp',
                  );
                },
                child: const Text('Open Picker'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Picker'));
      await tester.pumpAndSettle();

      // Verify header and suggested section
      expect(find.text('Gợi ý & Chọn Ảnh Mẫu Thông Minh'), findsOneWidget);
      expect(find.textContaining('Ảnh gợi ý phù hợp nhất'), findsOneWidget);

      // Verify search input
      expect(find.byType(TextField), findsOneWidget);

      // Tap on a suggested image card to select it
      final firstCard = find.text('Bàn ăn mặt đá cẩm thạch chống xước & Bàn trà sofa, Bàn cafe');
      expect(firstCard, findsWidgets);
      await tester.tap(firstCard.first);
      await tester.pumpAndSettle();

      expect(selectedUrl, isNotNull);
      expect(selectedUrl, contains('images.unsplash.com'));
    });
  });

  group('Milestone 3: ProductDetailPage allowSale & RBAC Tests', () {
    testWidgets('ProductDetailPage displays Cho phép bán switch and badge for inactive product',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockRepo = _MockProductRepository([sampleProductDisabled]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productRepositoryProvider.overrideWithValue(mockRepo),
            transactionsByProductProvider('prod_02')
                .overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: sampleProductDisabled),
        ),
      );

      await tester.pumpAndSettle();

      // Verify "Ngừng kinh doanh" badge is visible
      expect(find.text('Ngừng kinh doanh'), findsWidgets);

      // Verify switch is present with "Cho phép bán"
      expect(find.text('Cho phép bán'), findsOneWidget);
      expect(find.textContaining('Ngừng kinh doanh (Tự động ẩn khỏi màn hình POS)'), findsOneWidget);

      // Toggle switch to active
      final switchFinder = find.byType(Switch);
      expect(switchFinder, findsOneWidget);
      await tester.tap(switchFinder);
      await tester.pumpAndSettle();

      expect(mockRepo.lastUpserted?.allowSale, isTrue);
    });

    testWidgets('Staff cannot toggle Cho phép bán switch on ProductDetailPage',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockRepo = _MockProductRepository([sampleProductActive]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            productRepositoryProvider.overrideWithValue(mockRepo),
            transactionsByProductProvider('prod_01')
                .overrideWith((ref) => Stream.value([])),
          ],
          child: const ProductDetailPage(product: sampleProductActive),
        ),
      );

      await tester.pumpAndSettle();

      // Switch should be disabled for staff
      final switchWidget = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(switchWidget.onChanged, isNull);
    });
  });

  group('Milestone 3: POSPage allowSale Filtering Tests', () {
    testWidgets('POSPage displays active products and completely hides inactive products',
        (tester) async {
      final mockProducts = [sampleProductActive, sampleProductDisabled];

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value(mockProducts)),
            cartProvider.overrideWith((ref) => CartNotifier()),
          ],
          child: const POSPage(),
        ),
      );

      await tester.pumpAndSettle();

      // Active product MUST be visible
      expect(find.text('Nước ngọt Coca Cola 330ml'), findsOneWidget);

      // Inactive product MUST be hidden
      expect(find.text('Bia Hết Hạn Ngừng Bán'), findsNothing);
    });
  });

  group('Milestone 2 & 3: AddProductPage Integration Tests', () {
    testWidgets('AddProductPage shows Cho phép bán switch and allows smart sample image picker',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final mockRepo = _MockProductRepository([]);

      await tester.pumpWidget(
        _buildTestApp(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            productRepositoryProvider.overrideWithValue(mockRepo),
          ],
          child: const AddProductPage(),
        ),
      );

      await tester.pumpAndSettle();

      // Verify switch is present and enabled
      expect(find.text('Cho phép bán'), findsOneWidget);
      expect(find.textContaining('Đang kinh doanh'), findsOneWidget);

      // Open Image Source Sheet
      await tester.tap(find.text('Thêm ảnh sản phẩm'));
      await tester.pumpAndSettle();

      // Verify smart sample image suggestion option is present
      expect(find.text('Gợi ý ảnh mẫu thông minh'), findsOneWidget);
    });
  });
}
