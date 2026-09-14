import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventory/inventory_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/core/services/fifo_calculator.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/product_unit.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

// --- Test Fakes & Mock Infrastructure ---

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
        branchStocks: {'store_001': newStock, 'store_002': 0},
      );
    }
  }
}

class FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  Stream<List<InventoryTransaction>> watchAll() => Stream.value(transactions);

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) =>
      Stream.value(transactions.where((t) => t.productId == productId).toList());

  @override
  Future<void> record(InventoryTransaction transaction) async {
    transactions.add(transaction);
  }

  Future<List<InventoryTransaction>> fetchByProduct(String productId) async =>
      transactions.where((t) => t.productId == productId).toList();

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
      DateTime startDate, DateTime endDate) {
    return Stream.value(transactions
        .where((t) =>
            t.date.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            t.date.isBefore(endDate.add(const Duration(seconds: 1))))
        .toList());
  }
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

Widget _wrapWithApp({
  required Widget child,
  required UserAccount user,
  required String currentStoreId,
  FakeProductRepository? productRepo,
  FakeInventoryRepository? inventoryRepo,
  List<Category>? categories,
  List<Branch>? branches,
  Map<String, String>? availableStores,
}) {
  final pRepo = productRepo ?? FakeProductRepository();
  final iRepo = inventoryRepo ?? FakeInventoryRepository();
  final cats = categories ??
      [
        const Category(id: 'cat_01', name: 'Đồ uống'),
        const Category(id: 'cat_02', name: 'Gia vị'),
        const Category(id: 'cat_03', name: 'Gia dụng'),
        const Category(id: 'cat_04', name: 'Lương thực'),
      ];
  final brs = branches ??
      const [
        Branch('store_001', 'Chi nhánh Đông Thắng'),
        Branch('store_002', 'Chi nhánh Thới Bình'),
      ];
  final stores = availableStores ??
      {
        'store_001': 'Chi nhánh Đông Thắng',
        'store_002': 'Chi nhánh Thới Bình',
      };

  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => _FakeAuthNotifier(user)),
      currentStoreIdProvider.overrideWithValue(currentStoreId),
      productRepositoryProvider.overrideWithValue(pRepo),
      productListProvider.overrideWith((ref) => Stream.value(pRepo.products)),
      categoryListProvider.overrideWith((ref) => Stream.value(cats)),
      branchesProvider.overrideWithValue(brs),
      availableStoresProvider.overrideWith((ref) => Future.value(stores)),
      inventoryRepositoryProvider.overrideWithValue(iRepo),
      transactionsByProductProvider.overrideWith((ref, id) =>
          Stream.value(iRepo.transactions.where((t) => t.productId == id).toList())),
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

  const supervisorUser = UserAccount(
    username: 'supervisor_hoang',
    displayName: 'Hoàng Quản Lý',
    role: 'supervisor',
    storeId: 'store_001',
  );

  group('Tier 4: Real-World Retail Store Application Scenarios', () {
    // =========================================================================
    // Scenario S1: Multi-Branch Restock & Distribution Workflow
    // =========================================================================
    testWidgets(
        'Scenario S1 [Multi-Branch Restock & Distribution]: Central shipment imported to store_001, distributed to store_002 with preserved cost, and sold with accurate COGS and UI parity',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final baseTime = DateTime(2024, 10, 1, 8, 0);

      // 1. Initial State: Central supplier delivers 100 units of "Dầu Ăn Simply 1L" to store_001 @ 45,000 VND
      var simplyProduct = const Product(
        id: 'prod_simply_1l',
        name: 'Dầu Ăn Đậu Nành Simply 1L',
        code: 'SIMPLY01',
        price: 65000,
        costPrice: 45000,
        branchStocks: {'store_001': 100, 'store_002': 0},
        category: 'Gia vị',
      );

      final productRepo = FakeProductRepository([simplyProduct]);
      final inventoryRepo = FakeInventoryRepository();

      // Log Central Import in store_001
      final centralImportTx = InventoryTransaction(
        id: 'tx_s1_central_import',
        productId: simplyProduct.id,
        type: TransactionType.import,
        quantity: 100,
        date: baseTime,
        note: 'Nhập kho trung tâm từ Nhà Cung Cấp Simply',
        importPrice: 45000,

      );
      await inventoryRepo.record(centralImportTx);

      final store1Fifo = FifoCalculator([centralImportTx]);

      // 2. Warehouse Manager transfers 40 units from store_001 to store_002
      // Deduct from store_001 FIFO queue
      final exportCost = store1Fifo.calculateCostForSale(
        productId: simplyProduct.id,
        quantity: 40,
        saleDate: baseTime.add(const Duration(hours: 2)),
      );
      expect(exportCost, equals(1800000)); // 40 * 45,000 = 1,800,000 VND
      expect(store1Fifo.getInventoryLots(simplyProduct.id)[0].remainingQuantity, equals(60));

      // Target store_002 receives 40 units with preserved unit cost 45,000 VND
      final transferImportTx = InventoryTransaction(
        id: 'tx_s2_transfer_receive',
        productId: simplyProduct.id,
        type: TransactionType.import,
        quantity: 40,
        date: baseTime.add(const Duration(hours: 3)),
        note: 'Nhận chuyển kho 40 chai từ Chi nhánh Đông Thắng',
        importPrice: 45000,

      );
      await inventoryRepo.record(transferImportTx);

      final store2Fifo = FifoCalculator([transferImportTx]);

      // Update product branchStocks in database
      simplyProduct = simplyProduct.copyWith(
        branchStocks: {'store_001': 60, 'store_002': 40},
      );
      await productRepo.upsert(simplyProduct);

      // Total network stock must remain constant at 100
      expect(simplyProduct.stock, equals(100));

      // 3. Customer buys 15 units at store_002 (POS Sale)
      final saleCost = store2Fifo.calculateCostForSale(
        productId: simplyProduct.id,
        quantity: 15,
        saleDate: baseTime.add(const Duration(hours: 5)),
      );
      expect(saleCost, equals(675000)); // 15 * 45,000 = 675,000 VND
      final profit = (15 * 65000) - saleCost;
      expect(profit, equals(300000)); // 975,000 - 675,000 = 300,000 VND
      final margin = FifoCalculator.calculateProfitMargin(15 * 65000, saleCost);
      expect(margin, closeTo(30.77, 0.01));

      // store_002 remaining stock becomes 25
      simplyProduct = simplyProduct.copyWith(
        branchStocks: {'store_001': 60, 'store_002': 25},
      );
      await productRepo.upsert(simplyProduct);

      // 4. UI Parity Verification: Render ProductTile and ProductDetailPage
      await tester.pumpWidget(_wrapWithApp(
        child: Scaffold(body: ProductTile(product: simplyProduct)),
        user: supervisorUser,
        currentStoreId: 'store_001',
        productRepo: productRepo,
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 60 | TB: 25'), findsOneWidget);
      expect(find.text('Tồn: 85'), findsOneWidget);

      await tester.pumpWidget(_wrapWithApp(
        child: ProductDetailPage(product: simplyProduct),
        user: supervisorUser,
        currentStoreId: 'store_001',
        productRepo: productRepo,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('25'), findsOneWidget);
      expect(find.text('Tổng: 85'), findsOneWidget);
    });

    // =========================================================================
    // Scenario S2: POS Peak-Hour Multi-Store Sales with Oversold Fallback & Independent Costing
    // =========================================================================
    test(
        'Scenario S2 [POS Peak-Hour Sales]: Interleaved peak-hour sales at store_001 and store_002 compute independent COGS and handle oversold fallback without cross-store bleed',
        () {
      final baseDate = DateTime(2024, 10, 5, 17, 0); // 5:00 PM rush hour

      // Setup store_001: Lot A (20 @ 30k), Lot B (30 @ 35k). Total = 50. Price = 50k. Fallback = 35k.
      final s1Lots = [
        InventoryTransaction(
          id: 's1_lot_a',
          productId: 'prod_rush',
          type: TransactionType.import,
          quantity: 20,
          date: baseDate,
          note: 'Store 1 Lot A',
          importPrice: 30000,
        ),
        InventoryTransaction(
          id: 's1_lot_b',
          productId: 'prod_rush',
          type: TransactionType.import,
          quantity: 30,
          date: baseDate.add(const Duration(hours: 1)),
          note: 'Store 1 Lot B',
          importPrice: 35000,
        ),
      ];

      // Setup store_002: Lot X (15 @ 32k), Lot Y (15 @ 38k). Total = 30. Price = 52k. Fallback = 38k.
      final s2Lots = [
        InventoryTransaction(
          id: 's2_lot_x',
          productId: 'prod_rush',
          type: TransactionType.import,
          quantity: 15,
          date: baseDate,
          note: 'Store 2 Lot X',
          importPrice: 32000,
        ),
        InventoryTransaction(
          id: 's2_lot_y',
          productId: 'prod_rush',
          type: TransactionType.import,
          quantity: 15,
          date: baseDate.add(const Duration(hours: 1)),
          note: 'Store 2 Lot Y',
          importPrice: 38000,
        ),
      ];

      final trackerS1 = FifoCalculator(s1Lots);
      final trackerS2 = FifoCalculator(s2Lots);

      // --- Peak Hour Rush: Interleaved Sales ---

      // 1. Store 1 Order 1: Sells 15 units (draws from Lot A)
      final s1Cost1 = trackerS1.calculateCostForSale(
        productId: 'prod_rush',
        quantity: 15,
        saleDate: baseDate.add(const Duration(minutes: 10)),
        fallbackCostPrice: 35000,
      );
      expect(s1Cost1, equals(450000)); // 15 * 30k

      // 2. Store 2 Order 1: Sells 10 units (draws from Lot X)
      final s2Cost1 = trackerS2.calculateCostForSale(
        productId: 'prod_rush',
        quantity: 10,
        saleDate: baseDate.add(const Duration(minutes: 15)),
        fallbackCostPrice: 38000,
      );
      expect(s2Cost1, equals(320000)); // 10 * 32k

      // 3. Store 1 Order 2: Sells 10 units (5 from Lot A + 5 from Lot B)
      final s1Cost2 = trackerS1.calculateCostForSale(
        productId: 'prod_rush',
        quantity: 10,
        saleDate: baseDate.add(const Duration(minutes: 25)),
        fallbackCostPrice: 35000,
      );
      expect(s1Cost2, equals(325000)); // 5 * 30k + 5 * 35k = 150k + 175k = 325,000 VND

      // 4. Store 2 Order 2: Sells 10 units (5 from Lot X + 5 from Lot Y)
      final s2Cost2 = trackerS2.calculateCostForSale(
        productId: 'prod_rush',
        quantity: 10,
        saleDate: baseDate.add(const Duration(minutes: 35)),
        fallbackCostPrice: 38000,
      );
      expect(s2Cost2, equals(350000)); // 5 * 32k + 5 * 38k = 160k + 190k = 350,000 VND

      // 5. Store 1 Order 3 (Oversold): Sells 30 units (Available = 25 in Lot B -> deficit of 5 units)
      final s1Cost3 = trackerS1.calculateCostForSale(
        productId: 'prod_rush',
        quantity: 30,
        saleDate: baseDate.add(const Duration(minutes: 45)),
        fallbackCostPrice: 35000,
      );
      // 25 * 35k (Lot B) + 5 * 35k (Fallback) = 875,000 + 175,000 = 1,050,000 VND
      expect(s1Cost3, equals(1050000));

      // 6. Store 2 Order 3: Sells 5 units (from Lot Y)
      final s2Cost3 = trackerS2.calculateCostForSale(
        productId: 'prod_rush',
        quantity: 5,
        saleDate: baseDate.add(const Duration(minutes: 55)),
        fallbackCostPrice: 38000,
      );
      expect(s2Cost3, equals(190000)); // 5 * 38k

      // --- Financial & Lot Assertions ---

      // Store 1 totals:
      final totalS1Cogs = s1Cost1 + s1Cost2 + s1Cost3;
      expect(totalS1Cogs, equals(1825000)); // 450k + 325k + 1050k = 1,825,000 VND
      const totalS1Revenue = 55 * 50000.0; // 55 units sold @ 50k = 2,750,000 VND
      expect(totalS1Revenue - totalS1Cogs, equals(925000)); // Profit = 925,000 VND

      // Store 2 totals:
      final totalS2Cogs = s2Cost1 + s2Cost2 + s2Cost3;
      expect(totalS2Cogs, equals(860000)); // 320k + 350k + 190k = 860,000 VND
      const totalS2Revenue = 25 * 52000.0; // 25 units sold @ 52k = 1,300,000 VND
      expect(totalS2Revenue - totalS2Cogs, equals(440000)); // Profit = 440,000 VND

      // Verify no negative remaining quantities in lot queues
      final s1LotsResult = trackerS1.getInventoryLots('prod_rush');
      expect(s1LotsResult[0].remainingQuantity, equals(0));
      expect(s1LotsResult[1].remainingQuantity, equals(0));

      final s2LotsResult = trackerS2.getInventoryLots('prod_rush');
      expect(s2LotsResult[0].remainingQuantity, equals(0));
      expect(s2LotsResult[1].remainingQuantity, equals(5)); // Exactly 5 units @ 38k remaining!
    });

    // =========================================================================
    // Scenario S3: Physical Inventory Audit & Variance Reconcile with Ledger Trail
    // =========================================================================
    testWidgets(
        'Scenario S3 [Inventory Audit & Reconcile]: Physical stock discrepancy in store_001 (-6) and store_002 (+3) adjusted via ProductDetailPage generates structured audit transactions and updates FIFO queues',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Initial product: "Gạo ST25 5kg", costPrice = 160,000 VND
      const initialProduct = Product(
        id: 'prod_gao_st25',
        name: 'Gạo ST25 Ông Cua Túi 5kg',
        code: 'ST25-5KG',
        price: 210000,
        costPrice: 160000,
        branchStocks: {'store_001': 40, 'store_002': 25}, // Total = 65
        category: 'Lương thực',
      );

      final pRepo = FakeProductRepository([initialProduct]);
      final iRepo = FakeInventoryRepository();

      // --- 1. Audit store_001: Discrepancy 40 -> 34 (-6 variance) ---
      await tester.pumpWidget(_wrapWithApp(
        child: const ProductDetailPage(product: initialProduct),
        user: supervisorUser,
        currentStoreId: 'store_001',
        productRepo: pRepo,
        inventoryRepo: iRepo,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      // Pre-fill check
      expect(find.widgetWithText(TextFormField, '40'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, '40'), '34');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // Assert store_001 audit transaction
      expect(iRepo.transactions.length, equals(1));
      final s1Audit = iRepo.transactions.first;
      expect(s1Audit.productId, equals(initialProduct.id));
      expect(s1Audit.quantity, equals(6));
      expect(s1Audit.type, equals(TransactionType.inventoryAudit));
      expect(s1Audit.note, contains('Tồn cũ: 40 -> Tồn mới: 34, chênh lệch: -6'));

      final prodAfterS1 = pRepo.lastUpsertedProduct!;
      expect(prodAfterS1.branchStocks['store_001'], equals(34));
      expect(prodAfterS1.branchStocks['store_002'], equals(25)); // Untouched!
      expect(prodAfterS1.stock, equals(59));

      // --- 2. Audit store_002: Discrepancy 25 -> 28 (+3 variance) ---
      await tester.pumpWidget(_wrapWithApp(
        child: ProductDetailPage(product: prodAfterS1),
        user: supervisorUser,
        currentStoreId: 'store_002',
        productRepo: pRepo,
        inventoryRepo: iRepo,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sửa'));
      await tester.pumpAndSettle();

      // Pre-fill check
      expect(find.widgetWithText(TextFormField, '25'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, '25'), '28');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // Assert store_002 audit transaction
      expect(iRepo.transactions.length, equals(2));
      final s2Audit = iRepo.transactions.last;
      expect(s2Audit.productId, equals(initialProduct.id));
      expect(s2Audit.quantity, equals(3));
      expect(s2Audit.type, equals(TransactionType.inventoryAudit));
      expect(s2Audit.note, contains('Tồn cũ: 25 -> Tồn mới: 28, chênh lệch: +3'));

      final prodAfterS2 = pRepo.lastUpsertedProduct!;
      expect(prodAfterS2.branchStocks['store_001'], equals(34));
      expect(prodAfterS2.branchStocks['store_002'], equals(28));
      expect(prodAfterS2.stock, equals(62)); // 34 + 28 = 62

      // --- 3. Verify ProductTile and Breakdown Table reflect audited counts ---
      await tester.pumpWidget(_wrapWithApp(
        child: Scaffold(body: ProductTile(product: prodAfterS2)),
        user: supervisorUser,
        currentStoreId: 'store_001',
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 34 | TB: 28'), findsOneWidget);
      expect(find.text('Tồn: 62'), findsOneWidget);
    });

    // =========================================================================
    // Scenario S4: Defective Goods Customer Return & Immediate Resale
    // =========================================================================
    test(
        'Scenario S4 [Customer Return & Resale]: Customer returns pristine item to store_002, prepends lot at original cost, and subsequent resale draws returned lot before higher cost new stock',
        () {
      final baseDate = DateTime(2024, 10, 10, 9, 0);

      // Step 1: Initial sale of 4 units @ cost 600,000 VND
      final initialImportTx = InventoryTransaction(
        id: 'tx_s2_initial_batch',
        productId: 'prod_sharp_cooker',
        type: TransactionType.import,
        quantity: 10,
        date: baseDate,
        note: 'Lô Nồi cơm điện Sharp đầu tiên',
        importPrice: 600000,

      );

      final fifoStore2 = FifoCalculator([initialImportTx]);

      // Day 1: Customer A buys 4 units
      final customerACost = fifoStore2.calculateCostForSale(
        productId: 'prod_sharp_cooker',
        quantity: 4,
        saleDate: baseDate.add(const Duration(hours: 2)),
      );
      expect(customerACost, equals(2400000)); // 4 * 600,000 VND

      // Day 2: Store receives new batch of 5 units @ higher cost 650,000 VND
      final newBatchTx = InventoryTransaction(
        id: 'tx_s2_new_batch',
        productId: 'prod_sharp_cooker',
        type: TransactionType.import,
        quantity: 5,
        date: baseDate.add(const Duration(days: 1)),
        note: 'Lô Nồi cơm điện đợt 2 (giá tăng)',
        importPrice: 650000,

      );

      final lots = fifoStore2.getInventoryLots('prod_sharp_cooker');
      lots.add(
        InventoryLot(
          transactionId: newBatchTx.id,
          importDate: newBatchTx.date,
          importPrice: 650000,
          remainingQuantity: 5,
        ),
      );

      // Queue state: [Lot 1: 6 @ 600k, Lot 2: 5 @ 650k]
      expect(lots.length, equals(2));
      expect(lots[0].remainingQuantity, equals(6));
      expect(lots[1].remainingQuantity, equals(5));

      // Day 3: Customer A returns 2 units (cost 600,000 VND)
      // Case 6: Prepend to head of store_002 queue
      lots.insert(
        0,
        InventoryLot(
          transactionId: 'tx_return_sharp',
          importDate: baseDate.add(const Duration(days: 2)),
          importPrice: 600000,
          remainingQuantity: 2,
        ),
      );

      // Queue state: [Return Lot: 2 @ 600k, Lot 1: 6 @ 600k, Lot 2: 5 @ 650k]
      expect(lots.length, equals(3));
      expect(lots[0].remainingQuantity, equals(2));
      expect(lots[0].importPrice, equals(600000));

      // Day 3: Customer B buys 3 units @ new retail price 900,000 VND
      // Consumes: 2 units from Return Lot @ 600k + 1 unit from Lot 1 @ 600k = 1,800,000 VND
      final customerBCost = fifoStore2.calculateCostForSale(
        productId: 'prod_sharp_cooker',
        quantity: 3,
        saleDate: baseDate.add(const Duration(days: 2, hours: 4)),
      );
      expect(customerBCost, equals(1800000));

      const customerBRevenue = 3 * 900000.0;
      final customerBProfit = customerBRevenue - customerBCost;
      expect(customerBProfit, equals(900000)); // 2,700,000 - 1,800,000 = 900,000 VND

      // Remaining in queue: [Lot 1: 5 @ 600k, Lot 2: 5 @ 650k]
      expect(lots[0].remainingQuantity, equals(0)); // Return lot consumed
      expect(lots[1].remainingQuantity, equals(5)); // Lot 1 has 5 left
      expect(lots[2].remainingQuantity, equals(5)); // Lot 2 has 5 left
    });

    // =========================================================================
    // Scenario S5: Complete Multi-Day Multi-Store Business Lifecycle Workflow
    // =========================================================================
    testWidgets(
        'Scenario S5 [Complete Multi-Day Lifecycle]: Comprehensive 7-day multi-store operational simulation with restock, POS sales, transfer, audits (+/-), returns, rush sales, and end-of-week ledger parity',
        (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final day1 = DateTime(2024, 11, 1, 8, 0);

      // --- DAY 1: Initial Restock ---
      // store_001 imports 50 units @ 100,000 VND
      // store_002 imports 30 units @ 110,000 VND
      final s1Txs = <InventoryTransaction>[
        InventoryTransaction(
          id: 'd1_s1_imp',
          productId: 'prod_lifecycle_full',
          type: TransactionType.import,
          quantity: 50,
          date: day1,
          note: 'Day 1 Restock Store 1',
          importPrice: 100000,
        ),
      ];

      final s2Txs = <InventoryTransaction>[
        InventoryTransaction(
          id: 'd1_s2_imp',
          productId: 'prod_lifecycle_full',
          type: TransactionType.import,
          quantity: 30,
          date: day1,
          note: 'Day 1 Restock Store 2',
          importPrice: 110000,
        ),
      ];

      final trackerS1 = FifoCalculator(s1Txs);
      final trackerS2 = FifoCalculator(s2Txs);

      var lifecycleProduct = const Product(
        id: 'prod_lifecycle_full',
        name: 'Chảo Chống Dính Tefal 28cm',
        code: 'TEFAL28',
        price: 180000,
        costPrice: 100000,
        branchStocks: {'store_001': 50, 'store_002': 30},
        category: 'Gia dụng',
      );

      final pRepo = FakeProductRepository([lifecycleProduct]);
      final iRepo = FakeInventoryRepository();
      await iRepo.record(s1Txs.first);
      await iRepo.record(s2Txs.first);

      // --- DAY 2: Weekday POS Sales ---
      // store_001 sells 15 units
      final d2CostS1 = trackerS1.calculateCostForSale(
        productId: 'prod_lifecycle_full',
        quantity: 15,
        saleDate: day1.add(const Duration(days: 1)),
      );
      expect(d2CostS1, equals(1500000)); // 15 * 100k

      // store_002 sells 8 units
      final d2CostS2 = trackerS2.calculateCostForSale(
        productId: 'prod_lifecycle_full',
        quantity: 8,
        saleDate: day1.add(const Duration(days: 1)),
      );
      expect(d2CostS2, equals(880000)); // 8 * 110k

      lifecycleProduct = lifecycleProduct.copyWith(
        branchStocks: {'store_001': 35, 'store_002': 22},
      );
      await pRepo.upsert(lifecycleProduct);
      expect(lifecycleProduct.stock, equals(57));

      // --- DAY 3: Inter-Store Rebalance Transfer ---
      // store_001 transfers 10 units to store_002
      final d3TransferCost = trackerS1.calculateCostForSale(
        productId: 'prod_lifecycle_full',
        quantity: 10,
        saleDate: day1.add(const Duration(days: 2)),
      );
      expect(d3TransferCost, equals(1000000)); // 10 * 100k

      // Target store_002 receives 10 units @ preserved cost 100,000 VND
      final s2Lots = trackerS2.getInventoryLots('prod_lifecycle_full');
      s2Lots.add(
        InventoryLot(
          transactionId: 'd3_s2_transfer_in',
          importDate: day1.add(const Duration(days: 2)),
          importPrice: 100000,
          remainingQuantity: 10,
        ),
      );

      lifecycleProduct = lifecycleProduct.copyWith(
        branchStocks: {'store_001': 25, 'store_002': 32},
      );
      await pRepo.upsert(lifecycleProduct);
      expect(lifecycleProduct.stock, equals(57)); // Unchanged total!

      // --- DAY 4: Mid-Week Physical Audit ---
      // store_001 has -1 unit variance (damaged) -> drains 1 unit
      final d4S1Drain = trackerS1.calculateCostForSale(
        productId: 'prod_lifecycle_full',
        quantity: 1,
        saleDate: day1.add(const Duration(days: 3)),
      );
      expect(d4S1Drain, equals(100000));

      // store_002 has +2 units variance (found in backroom @ 110,000 VND)
      s2Lots.add(
        InventoryLot(
          transactionId: 'd4_s2_audit_pos',
          importDate: day1.add(const Duration(days: 3)),
          importPrice: 110000,
          remainingQuantity: 2,
        ),
      );

      lifecycleProduct = lifecycleProduct.copyWith(
        branchStocks: {'store_001': 24, 'store_002': 34},
      );
      await pRepo.upsert(lifecycleProduct);
      expect(lifecycleProduct.stock, equals(58));

      // --- DAY 5: Customer Return at Store 2 ---
      // Customer returns 2 units purchased on Day 2 @ 110,000 VND
      // Case 6: Prepend to head of store_002 queue
      s2Lots.insert(
        0,
        InventoryLot(
          transactionId: 'd5_s2_return',
          importDate: day1.add(const Duration(days: 4)),
          importPrice: 110000,
          remainingQuantity: 2,
        ),
      );

      lifecycleProduct = lifecycleProduct.copyWith(
        branchStocks: {'store_001': 24, 'store_002': 36},
      );
      await pRepo.upsert(lifecycleProduct);
      expect(lifecycleProduct.stock, equals(60));

      // --- DAY 6: Weekend Super Sale Rush ---
      // store_001 sells 10 units
      final d6CostS1 = trackerS1.calculateCostForSale(
        productId: 'prod_lifecycle_full',
        quantity: 10,
        saleDate: day1.add(const Duration(days: 5)),
      );
      expect(d6CostS1, equals(1000000)); // 10 * 100k

      // store_002 sells 20 units
      // Queue has:
      // - Index 0: 2 @ 110k (Return)
      // - Index 1: 22 @ 110k (Day 1 remainder)
      // - Index 2: 10 @ 100k (Day 3 transfer)
      // - Index 3: 2 @ 110k (Day 4 audit)
      // Sale of 20 units: 2 @ 110k + 18 @ 110k = 20 * 110k = 2,200,000 VND
      final d6CostS2 = trackerS2.calculateCostForSale(
        productId: 'prod_lifecycle_full',
        quantity: 20,
        saleDate: day1.add(const Duration(days: 5)),
      );
      expect(d6CostS2, equals(2200000));

      lifecycleProduct = lifecycleProduct.copyWith(
        branchStocks: {'store_001': 14, 'store_002': 16},
      );
      await pRepo.upsert(lifecycleProduct);
      expect(lifecycleProduct.stock, equals(30)); // Final network total

      // --- DAY 7: End-of-Week Reconciliation & UI Parity Verification ---
      expect(trackerS1.getInventoryLots('prod_lifecycle_full')[0].remainingQuantity, equals(14));
      // store_002 remaining lots: Index 1 has 4 @ 110k, Index 2 has 10 @ 100k, Index 3 has 2 @ 110k -> Total = 16
      final s2TotalRemaining = s2Lots.fold(0, (sum, lot) => sum + lot.remainingQuantity);
      expect(s2TotalRemaining, equals(16));

      // Render ProductTile
      await tester.pumpWidget(_wrapWithApp(
        child: Scaffold(body: ProductTile(product: lifecycleProduct)),
        user: supervisorUser,
        currentStoreId: 'store_001',
        productRepo: pRepo,
      ));
      await tester.pumpAndSettle();

      expect(find.text('ĐT: 14 | TB: 16'), findsOneWidget);
      expect(find.text('Tồn: 30'), findsOneWidget);

      // Render ProductDetailPage
      await tester.pumpWidget(_wrapWithApp(
        child: ProductDetailPage(product: lifecycleProduct),
        user: supervisorUser,
        currentStoreId: 'store_001',
        productRepo: pRepo,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Phân bổ tồn kho theo chi nhánh'), findsOneWidget);
      expect(find.text('Chi nhánh Đông Thắng'), findsOneWidget);
      expect(find.text('14'), findsOneWidget);
      expect(find.text('Chi nhánh Thới Bình'), findsOneWidget);
      expect(find.text('16'), findsOneWidget);
      expect(find.text('Tổng: 30'), findsOneWidget);
      expect(find.text('Tổng tồn toàn chuỗi'), findsOneWidget);
    });

    // =========================================================================
    // Scenario S6: Multi-Unit Packaging Distribution & POS Conversion Lifecycle
    // =========================================================================
    test(
        'Scenario S6 [Multi-Unit Packaging & Conversion]: Multi-unit beverage (Lon, Lốc=6, Thùng=24) calculates base stock depletion and FIFO unit costing across packaging tiers',
        () {
      final baseDate = DateTime(2024, 12, 1);

      // Units definition
      const units = [
        ProductUnit(
          id: 'u_lon',
          unitName: 'Lon',
          conversionRate: 1,
          price: 15000,
          costPrice: 10000,
          isDirectSale: true,
        ),
        ProductUnit(
          id: 'u_loc',
          unitName: 'Lốc (6 lon)',
          conversionRate: 6,
          price: 88000,
          costPrice: 60000,
          isDirectSale: true,
        ),
        ProductUnit(
          id: 'u_thung',
          unitName: 'Thùng (24 lon)',
          conversionRate: 24,
          price: 345000,
          costPrice: 240000,
          isDirectSale: true,
        ),
      ];

      expect(units.length, equals(3));
      expect(units[1].conversionRate, equals(6));
      expect(units[2].conversionRate, equals(24));

      // Base stock: 120 lon (5 thùng) @ 10,000 VND/lon in store_001
      final importTx = InventoryTransaction(
        id: 'tx_unit_imp',
        productId: 'prod_multi_unit',
        type: TransactionType.import,
        quantity: 120,
        date: baseDate,
        note: 'Nhập 5 thùng (120 lon) Bia',
        importPrice: 10000,
      );

      final fifo = FifoCalculator([importTx]);

      // Sale 1: Sells 2 Thùng (2 * 24 = 48 lon)
      final sale1Cost = fifo.calculateCostForSale(
        productId: 'prod_multi_unit',
        quantity: 2 * 24,
        saleDate: baseDate.add(const Duration(hours: 1)),
      );
      expect(sale1Cost, equals(480000)); // 48 * 10,000 VND

      // Sale 2: Sells 3 Lốc (3 * 6 = 18 lon)
      final sale2Cost = fifo.calculateCostForSale(
        productId: 'prod_multi_unit',
        quantity: 3 * 6,
        saleDate: baseDate.add(const Duration(hours: 2)),
      );
      expect(sale2Cost, equals(180000)); // 18 * 10,000 VND

      // Sale 3: Sells 4 Lon lẻ
      final sale3Cost = fifo.calculateCostForSale(
        productId: 'prod_multi_unit',
        quantity: 4,
        saleDate: baseDate.add(const Duration(hours: 3)),
      );
      expect(sale3Cost, equals(40000)); // 4 * 10,000 VND

      // Total sold: 48 + 18 + 4 = 70 lon. Remaining = 120 - 70 = 50 lon.
      final remainingLots = fifo.getInventoryLots('prod_multi_unit');
      expect(remainingLots[0].remainingQuantity, equals(50));

      // Revenue: (2 * 345k) + (3 * 88k) + (4 * 15k) = 690k + 264k + 60k = 1,014,000 VND
      const totalRevenue = (2 * 345000.0) + (3 * 88000.0) + (4 * 15000.0);
      final totalCost = sale1Cost + sale2Cost + sale3Cost; // 700,000 VND
      final grossProfit = totalRevenue - totalCost;
      expect(grossProfit, equals(314000)); // 1,014,000 - 700,000 = 314,000 VND
      final margin = FifoCalculator.calculateProfitMargin(totalRevenue, totalCost);
      expect(margin, closeTo(30.97, 0.01));
    });
  });
}
