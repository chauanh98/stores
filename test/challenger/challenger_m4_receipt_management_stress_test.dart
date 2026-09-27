import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';
import 'package:stores/presentation/inventories/pages/import_inventory_page.dart';
import 'package:stores/presentation/inventories/pages/stock_in_receipts_page.dart';

// ============================================================================
// ADVERSARIAL TEST HARNESS & SPY DEFINITIONS
// ============================================================================

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

/// Spying StockInReceiptRepository that stores receipts in memory and logs all operations.
class SpyStockInReceiptRepository implements StockInReceiptRepository {
  final Map<String, StockInReceipt> receipts = {};
  final List<String> operationLogs = [];

  String? lastSavedDraftId;
  StockInReceipt? lastSavedDraft;
  String? lastDeletedReceiptId;
  String? lastDeletedStoreId;

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    operationLogs.add('saveDraft:${receipt.id}');
    lastSavedDraftId = receipt.id;
    lastSavedDraft = receipt;
    receipts[receipt.id] = receipt;
    return receipt.id;
  }

  @override
  Future<void> updateDraft(StockInReceipt receipt) async {
    operationLogs.add('updateDraft:${receipt.id}');
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteDraft({
    required String storeId,
    required String receiptId,
  }) async {
    operationLogs.add('deleteDraft:$receiptId@$storeId');
    lastDeletedReceiptId = receiptId;
    lastDeletedStoreId = storeId;
    receipts.remove(receiptId);
  }

  @override
  Future<void> deleteReceipt({
    required String storeId,
    required String receiptId,
  }) async {
    operationLogs.add('deleteReceipt:$receiptId@$storeId');
    lastDeletedReceiptId = receiptId;
    lastDeletedStoreId = storeId;
    receipts.remove(receiptId);
  }

  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {
    operationLogs.add('cancelReceipt:${receipt.id}');
  }

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async =>
      receipts.values.toList();

  @override
  Future<StockInReceipt?> getReceiptById({
    required String storeId,
    required String receiptId,
  }) async =>
      receipts[receiptId];

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    operationLogs.add('saveReceipt:${receipt.id}');
    receipts[receipt.id] = receipt;
  }

  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) =>
      Stream.value(receipts.values.toList());

  @override
  Future<double?> getLatestImportPrice({
    required String storeId,
    required String productId,
  }) async =>
      null;
}

/// Strict spy ensuring NO inventory or product mutations occur.
class StrictInventorySpy implements InventoryRepository {
  int mutationCallCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final memberName = invocation.memberName.toString();
    if (!memberName.contains('watch') &&
        !memberName.contains('get') &&
        !memberName.contains('fetch')) {
      mutationCallCount++;
    }
    return super.noSuchMethod(invocation);
  }
}

/// Strict spy ensuring NO product mutations occur.
class StrictProductSpy implements ProductRepository {
  int mutationCallCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final memberName = invocation.memberName.toString();
    if (!memberName.contains('watch') &&
        !memberName.contains('get') &&
        !memberName.contains('fetch')) {
      mutationCallCount++;
    }
    return super.noSuchMethod(invocation);
  }
}

/// Strict spy ensuring NO supplier debt mutations occur.
class StrictSupplierSpy implements SupplierRepository {
  int mutationCallCount = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final memberName = invocation.memberName.toString();
    if (!memberName.contains('watch') &&
        !memberName.contains('get') &&
        !memberName.contains('fetch')) {
      mutationCallCount++;
    }
    return super.noSuchMethod(invocation);
  }
}

/// Spying CompleteStockInReceiptUseCase to capture completed receipts.
class SpyCompleteStockInReceiptUseCase extends CompleteStockInReceiptUseCase {
  StockInReceipt? lastCompletedReceipt;

  SpyCompleteStockInReceiptUseCase({
    required super.productRepository,
    required super.inventoryRepository,
    required super.supplierRepository,
    required super.receiptRepository,
  });

  @override
  Future<StockInReceipt> execute(StockInReceipt receipt) async {
    lastCompletedReceipt = receipt;
    return receipt.copyWith(status: 'completed');
  }
}

Widget _buildChallengerApp({
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

  const testAdminUser = UserAccount(
    username: 'admin_challenger',
    displayName: 'Challenger Admin',
    role: 'admin',
    storeId: 'store_001',
  );

  const testSupplier1 = Supplier(
    id: 'sup_stress_01',
    name: 'Công ty Cổ Phần Dược Phẩm Trung Ương',
    phone: '0909112233',
    code: 'NCC_TW',
    address: 'Hà Nội',
  );

  const testSupplier2 = Supplier(
    id: 'sup_stress_02',
    name: 'Tổng Kho Thiết Bị Y Tế Sài Gòn',
    phone: '0988776655',
    code: 'NCC_SG',
    address: 'TP.HCM',
  );

  final baseOverrides = [
    authProvider.overrideWith((ref) => _FakeAuthNotifier(testAdminUser)),
    supplierListNotifierProvider.overrideWith(
      () => _FakeSupplierListNotifier([testSupplier1, testSupplier2]),
    ),
    availableStoresProvider.overrideWith((ref) async => {
          'store_001': 'Chi nhánh Đông Thắng',
          'store_002': 'Chi nhánh Thới Bình',
        }),
    currentStoreIdProvider.overrideWith((ref) => 'store_001'),
    productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
    allStoresProductsProvider.overrideWith((ref) => Stream.value(<Product>[])),
    rawImportTransactionsStreamProvider
        .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
    allSupplierDebtTransactionsProvider
        .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
  ];

  // ==========================================================================
  // SECTION 1: 3-STATE FILTER CHIPS & MULTI-DIMENSIONAL STRESS TESTS
  // ==========================================================================
  group(
      'Adversarial Dimension 1: 3-State Filter Logic & Multi-Dimensional Stress',
      () {
    test(
        'Combinatorial status and date partition invariant: Completed + Draft + Cancelled strictly equals All',
        () {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day, 10, 0);
      final yesterday = today.subtract(const Duration(days: 1));
      final lastWeek = today.subtract(const Duration(days: 5));
      final lastMonth = today.subtract(const Duration(days: 35));

      final List<StockInReceipt> generatedDataset = [];

      final dates = [today, yesterday, lastWeek, lastMonth];
      final statuses = [
        'completed',
        'Đã nhập hàng',
        'hoan_thanh',
        'draft',
        'Phiếu tạm',
        'cancelled',
        'Đã hủy'
      ];
      final stores = ['store_001', 'store_002'];
      final suppliers = ['sup_stress_01', 'sup_stress_02', null];

      int idCounter = 1;
      for (final date in dates) {
        for (final status in statuses) {
          for (final store in stores) {
            for (final supplier in suppliers) {
              generatedDataset.add(
                StockInReceipt(
                  id: 'stress_rec_${idCounter++}',
                  importCode: 'PN_STRESS_$idCounter',
                  status: status,
                  date: date,
                  storeId: store,
                  supplierId: supplier,
                  supplierName: supplier != null ? 'NCC $supplier' : null,
                  createdBy: 'challenger',
                  items: [
                    StockInReceiptItem(
                      transactionId: 'tx_stress_$idCounter',
                      productId: 'prod_$idCounter',
                      productName: 'Thuốc $idCounter',
                      quantity: 5,
                      importPrice: 20000,
                    ),
                  ],
                ),
              );
            }
          }
        }
      }

      expect(generatedDataset.length, equals(4 * 7 * 2 * 3)); // 168 receipts

      // Test across multiple time ranges: today, last7Days, thisMonth, custom
      final timeRangesToTest = [
        OverviewTimeRange.today,
        OverviewTimeRange.last7Days,
        OverviewTimeRange.thisMonth,
        OverviewTimeRange.custom,
      ];

      for (final tr in timeRangesToTest) {
        final filterAll = StockInReceiptsFilterState(
          timeRange: tr,
          statusFilter: 'all',
          storeId: 'all',
        );
        final filterCompleted = StockInReceiptsFilterState(
          timeRange: tr,
          statusFilter: 'completed',
          storeId: 'all',
        );
        final filterDraft = StockInReceiptsFilterState(
          timeRange: tr,
          statusFilter: 'draft',
          storeId: 'all',
        );
        final filterCancelled = StockInReceiptsFilterState(
          timeRange: tr,
          statusFilter: 'cancelled',
          storeId: 'all',
        );

        final resultAll = filterStockInReceipts(generatedDataset, filterAll);
        final resultCompleted =
            filterStockInReceipts(generatedDataset, filterCompleted);
        final resultDraft =
            filterStockInReceipts(generatedDataset, filterDraft);
        final resultCancelled =
            filterStockInReceipts(generatedDataset, filterCancelled);

        // Invariant 1: Total partitioned subsets strictly equal 'all'
        expect(
          resultCompleted.length + resultDraft.length + resultCancelled.length,
          equals(resultAll.length),
          reason: 'Partition invariant violated for time range ${tr.name}',
        );

        // Invariant 2: Disjointness (no overlapping IDs between any subsets)
        final completedIds = resultCompleted.map((r) => r.id).toSet();
        final draftIds = resultDraft.map((r) => r.id).toSet();
        final cancelledIds = resultCancelled.map((r) => r.id).toSet();

        expect(completedIds.intersection(draftIds), isEmpty);
        expect(completedIds.intersection(cancelledIds), isEmpty);
        expect(draftIds.intersection(cancelledIds), isEmpty);

        // Invariant 3: Purity of status flags
        for (final r in resultCompleted) {
          expect(r.isCompleted, isTrue);
          expect(r.isDraft, isFalse);
          expect(r.isCancelled, isFalse);
        }
        for (final r in resultDraft) {
          expect(r.isDraft, isTrue);
          expect(r.isCompleted, isFalse);
          expect(r.isCancelled, isFalse);
        }
        for (final r in resultCancelled) {
          expect(r.isCancelled, isTrue);
          expect(r.isDraft, isFalse);
          expect(r.isCompleted, isFalse);
        }
      }
    });

    test(
        'Boundary millisecond precision: receipts exactly at start and end of range are captured',
        () {
      final now = DateTime.now();
      final startBoundary = DateTime(now.year, now.month, now.day, 0, 0, 0, 0);
      final endBoundary =
          DateTime(now.year, now.month, now.day, 23, 59, 59, 999);
      final justBeforeStart =
          startBoundary.subtract(const Duration(milliseconds: 1));
      final justAfterEnd = endBoundary.add(const Duration(milliseconds: 1));

      final boundaryDataset = [
        StockInReceipt(
          id: 'at_start',
          importCode: 'PN_START',
          status: 'draft',
          date: startBoundary,
          items: const [],
        ),
        StockInReceipt(
          id: 'at_end',
          importCode: 'PN_END',
          status: 'draft',
          date: endBoundary,
          items: const [],
        ),
        StockInReceipt(
          id: 'before_start',
          importCode: 'PN_BEFORE',
          status: 'draft',
          date: justBeforeStart,
          items: const [],
        ),
        StockInReceipt(
          id: 'after_end',
          importCode: 'PN_AFTER',
          status: 'draft',
          date: justAfterEnd,
          items: const [],
        ),
      ];

      const filter = StockInReceiptsFilterState(
        timeRange: OverviewTimeRange.today,
        statusFilter: 'draft',
      );

      final filtered = filterStockInReceipts(boundaryDataset, filter);
      final ids = filtered.map((r) => r.id).toList();

      expect(ids, contains('at_start'));
      expect(ids, contains('at_end'));
      expect(ids, isNot(contains('before_start')));
      expect(ids, isNot(contains('after_end')));
    });

    testWidgets(
        'Empty filter results render graceful empty state and reset button restores complete list',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Only completed receipts exist
      final onlyCompletedList = [
        StockInReceipt(
          id: 'rec_completed_only',
          importCode: 'PN_COMPLETED_ONLY',
          status: 'completed',
          date: DateTime.now(),
          storeId: 'store_001',
          items: const [
            StockInReceiptItem(
              transactionId: 'tx_comp_only',
              productId: 'p_only',
              productName: 'Sản phẩm hoàn thành',
              quantity: 5,
              importPrice: 50000,
            ),
          ],
        ),
      ];

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data(onlyCompletedList),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Completed is visible under 'Tất cả'
      expect(find.text('#PN_COMPLETED_ONLY'), findsOneWidget);

      // Switch to 'Phiếu tạm' where 0 drafts exist
      await tester.tap(find.byKey(const Key('filter_draft')));
      await tester.pumpAndSettle();

      // Verify empty state is displayed gracefully without crashes or overflow
      expect(find.text('#PN_COMPLETED_ONLY'), findsNothing);
      expect(find.text('Chưa có phiếu nhập kho nào'), findsOneWidget);
      expect(
        find.text(
            'Không tìm thấy kết quả phù hợp với các tiêu chí lọc hiện tại'),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);

      // Verify "Đặt lại bộ lọc" button in empty state
      final resetBtn = find.text('Đặt lại bộ lọc');
      expect(resetBtn, findsOneWidget);

      // Tapping "Đặt lại bộ lọc" resets filter
      await tester.tap(resetBtn);
      await tester.pumpAndSettle();

      // Receipts reappear
      expect(find.text('#PN_COMPLETED_ONLY'), findsOneWidget);
    });

    testWidgets(
        'Rapid asynchronous switching between status filter chips maintains UI consistency',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final mixedList = [
        StockInReceipt(
          id: 'c1',
          importCode: 'PN_C1',
          status: 'completed',
          date: DateTime.now(),
          items: const [],
        ),
        StockInReceipt(
          id: 'd1',
          importCode: 'PN_D1',
          status: 'draft',
          date: DateTime.now(),
          items: const [],
        ),
        StockInReceipt(
          id: 'x1',
          importCode: 'PN_X1',
          status: 'cancelled',
          date: DateTime.now(),
          items: const [],
        ),
      ];

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data(mixedList),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Rapidly tap all chips in sequence without pumpAndSettle between some taps
      await tester.tap(find.byKey(const Key('filter_draft')));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.byKey(const Key('filter_cancelled')));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.byKey(const Key('filter_completed')));
      await tester.pump(const Duration(milliseconds: 10));
      await tester.tap(find.byKey(const Key('filter_all')));
      await tester.pumpAndSettle();

      // All 3 should be visible
      expect(find.text('#PN_C1'), findsOneWidget);
      expect(find.text('#PN_D1'), findsOneWidget);
      expect(find.text('#PN_X1'), findsOneWidget);
      expect(find.text('3 phiếu nhập'), findsOneWidget);
    });
  });

  // ==========================================================================
  // SECTION 2: DRAFT TAP RESUMPTION & IN-PLACE EDITING STRESS TESTS
  // ==========================================================================
  group(
      'Adversarial Dimension 2: Draft Tap Resumption & Edit Invariant (No Duplicate IDs)',
      () {
    final richDraft = StockInReceipt(
      id: 'DRAFT_STRESS_EXACT_999',
      importCode: 'PN_DRAFT_EXACT_999',
      status: 'draft',
      storeId: 'store_001',
      supplierId: 'sup_stress_01',
      supplierName: 'Công ty Cổ Phần Dược Phẩm Trung Ương',
      supplierPhone: '0909112233',
      discount: 25000,
      paidAmount: 300000,
      paymentMethod: 'bank_transfer',
      note: 'Ghi chú phiếu tạm đặc biệt kiểm thử',
      date: DateTime(2026, 9, 25, 8, 30),
      createdAt: DateTime(2026, 9, 25, 8, 30),
      items: const [
        StockInReceiptItem(
          transactionId: 'tx_amox_01',
          productId: 'prod_amox',
          productName: 'Amoxicillin 500mg',
          productCode: 'AMOX500',
          quantity: 10,
          importPrice: 35000,
          unit: 'Hộp',
          note: 'Lô sản xuất 2026',
        ),
        StockInReceiptItem(
          transactionId: 'tx_para_01',
          productId: 'prod_para',
          productName: 'Paracetamol 500mg',
          productCode: 'PARA500',
          quantity: 20,
          importPrice: 15000,
          unit: 'Vỉ',
          note: '',
        ),
      ],
    );

    testWidgets(
        'Tapping draft card resumes in ImportInventoryPage with 100% field fidelity',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([richDraft]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Draft card is visible with draft badge
      expect(find.text('#PN_DRAFT_EXACT_999'), findsOneWidget);
      expect(find.byKey(const Key('badge_draft')), findsOneWidget);

      // Tap draft card -> opens ImportInventoryPage
      await tester.tap(find.text('#PN_DRAFT_EXACT_999'));
      await tester.pumpAndSettle();

      expect(find.byType(ImportInventoryPage), findsOneWidget);

      // 1. Verify code in title bar: "Phiếu PN_DRAFT_EXACT_999"
      expect(find.text('Phiếu PN_DRAFT_EXACT_999'), findsOneWidget);

      // 2. Verify supplier name is loaded
      expect(
        find.text('Công ty Cổ Phần Dược Phẩm Trung Ương'),
        findsOneWidget,
      );

      // 3. Verify all items and quantities are rendered
      expect(find.text('Amoxicillin 500mg'), findsOneWidget);
      expect(find.text('Paracetamol 500mg'), findsOneWidget);
      expect(find.byKey(const Key('stepper_qty_prod_amox')), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.byKey(const Key('stepper_qty_prod_para')), findsOneWidget);
      expect(find.text('20'), findsOneWidget);

      // 4. Verify summary bar calculations:
      // Amox: 10 * 35,000 = 350,000
      // Para: 20 * 15,000 = 300,000
      // Total goods: 650,000
      // Total qty: 30
      final currencyFormat = NumberFormat('#,###', 'vi_VN');
      expect(find.text('${currencyFormat.format(650000)} đ'), findsOneWidget);
      expect(find.text('2 mặt hàng • Số lượng: 30'), findsOneWidget);
    });

    testWidgets(
        'Modifying draft items and re-saving updates draft in-place without generating duplicate IDs',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final spyRepo = SpyStockInReceiptRepository();
      spyRepo.receipts[richDraft.id] = richDraft;

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptRepositoryProvider.overrideWithValue(spyRepo),
            saveStockInDraftUseCaseProvider.overrideWithValue(
              SaveStockInDraftUseCase(spyRepo),
            ),
          ],
          child: ImportInventoryPage(initialReceipt: richDraft),
        ),
      );
      await tester.pumpAndSettle();

      // Increment Amoxicillin quantity from 10 to 11 via stepper [+]
      final incBtn = find.byKey(const Key('stepper_inc_prod_amox'));
      expect(incBtn, findsOneWidget);
      await tester.tap(incBtn);
      await tester.pumpAndSettle();

      expect(find.text('11'), findsOneWidget);
      expect(find.text('2 mặt hàng • Số lượng: 31'), findsOneWidget);

      // Tap "Lưu tạm" button
      final saveDraftBtn = find.byKey(const Key('btn_save_draft'));
      expect(saveDraftBtn, findsOneWidget);
      await tester.tap(saveDraftBtn);
      await tester.pump(); // Show snackbar

      // VERIFICATION: Check spy repository state
      expect(spyRepo.lastSavedDraft, isNotNull);
      final saved = spyRepo.lastSavedDraft!;

      // Invariant 1: ID MUST BE PRESERVED (NO new random timestamp ID!)
      expect(
        saved.id,
        equals('DRAFT_STRESS_EXACT_999'),
        reason:
            'CRITICAL BUG: Draft ID was mutated or duplicated upon re-saving!',
      );

      // Invariant 2: Import code must be preserved
      expect(saved.importCode, equals('PN_DRAFT_EXACT_999'));

      // Invariant 3: Status remains 'draft'
      expect(saved.isDraft, isTrue);

      // Invariant 4: Items reflect the incremented quantity (11)
      final amoxItem =
          saved.items.firstWhere((i) => i.productId == 'prod_amox');
      expect(amoxItem.quantity, equals(11));

      // Invariant 5: Exactly 1 record exists in repository (NO duplicate ID generated!)
      expect(
        spyRepo.receipts.length,
        equals(1),
        reason: 'Duplicate draft receipt detected in database repository!',
      );
      expect(spyRepo.receipts.containsKey('DRAFT_STRESS_EXACT_999'), isTrue);
    });

    testWidgets(
        'Resumed draft can transition to completed receipt with ID preserved',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final spyRepo = SpyStockInReceiptRepository();
      final inventorySpy = StrictInventorySpy();
      final productSpy = StrictProductSpy();
      final supplierSpy = StrictSupplierSpy();

      final spyCompleteUseCase = SpyCompleteStockInReceiptUseCase(
        productRepository: productSpy,
        inventoryRepository: inventorySpy,
        supplierRepository: supplierSpy,
        receiptRepository: spyRepo,
      );

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            completeStockInReceiptUseCaseProvider
                .overrideWithValue(spyCompleteUseCase),
          ],
          child: ImportInventoryPage(initialReceipt: richDraft),
        ),
      );
      await tester.pumpAndSettle();

      // Tap "Tiếp tục" -> Navigate to Step 2
      final continueBtn = find.byKey(const Key('btn_continue'));
      expect(continueBtn, findsOneWidget);
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();

      // Now on Step 2 (StockInPaymentConfirmationView)
      expect(find.byKey(const Key('btn_payment_complete')), findsOneWidget);

      // Complete receipt
      await tester.tap(find.byKey(const Key('btn_payment_complete')));
      await tester.pump();

      // VERIFICATION: Check complete use case received identical ID
      expect(spyCompleteUseCase.lastCompletedReceipt, isNotNull);
      final completed = spyCompleteUseCase.lastCompletedReceipt!;
      expect(completed.id, equals('DRAFT_STRESS_EXACT_999'));
      expect(completed.status, equals('completed'));
    });
  });

  // ==========================================================================
  // SECTION 3: DRAFT DELETION & ZERO SIDE-EFFECT ISOLATION STRESS TESTS
  // ==========================================================================
  group(
      'Adversarial Dimension 3: Draft Deletion & Side-Effect Isolation (Zero Stock/Debt Mutation)',
      () {
    final draftToDelete = StockInReceipt(
      id: 'DRAFT_TO_DELETE_777',
      importCode: 'PN_DELETE_777',
      status: 'draft',
      storeId: 'store_001',
      supplierId: 'sup_stress_01',
      date: DateTime.now(),
      items: const [
        StockInReceiptItem(
          transactionId: 'tx_danger_01',
          productId: 'prod_danger',
          productName: 'Thuốc Độc Bảng A',
          quantity: 100,
          importPrice: 500000,
        ),
      ],
      discount: 0,
      paidAmount: 0,
    );

    testWidgets(
        'Dismissible swipe-to-dismiss prompts confirmation dialog and cleanly deletes draft on confirm',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final spyRepo = SpyStockInReceiptRepository();
      spyRepo.receipts[draftToDelete.id] = draftToDelete;

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptRepositoryProvider.overrideWithValue(spyRepo),
            deleteStockInReceiptUseCaseProvider.overrideWithValue(
              DeleteStockInReceiptUseCase(spyRepo),
            ),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([draftToDelete]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify Dismissible exists for draft
      final dismissibleFinder =
          find.byKey(Key('dismissible_draft_${draftToDelete.id}'));
      expect(dismissibleFinder, findsOneWidget);

      // 1. Swipe left to dismiss
      await tester.drag(dismissibleFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      // 2. Dialog appears
      expect(find.text('Xác nhận xóa'), findsOneWidget);
      expect(find.text('Xóa phiếu tạm này?'), findsOneWidget);

      // 3. User cancels first
      await tester.tap(find.byKey(const Key('btn_cancel_delete_draft')));
      await tester.pumpAndSettle();

      // Card is still present and repo was not deleted
      expect(find.text('#PN_DELETE_777'), findsOneWidget);
      expect(spyRepo.lastDeletedReceiptId, isNull);

      // 4. Swipe again and confirm
      await tester.drag(dismissibleFinder, const Offset(-500, 0));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_confirm_delete_draft')));
      await tester.pumpAndSettle();

      // Verified deletion executed in repo
      expect(spyRepo.lastDeletedReceiptId, equals('DRAFT_TO_DELETE_777'));
      expect(spyRepo.lastDeletedStoreId, equals('store_001'));
      expect(spyRepo.receipts.containsKey('DRAFT_TO_DELETE_777'), isFalse);
    });

    test(
        'Mathematical & Architectural Invariant: Deleting draft triggers ZERO stock mutations and ZERO debt mutations',
        () async {
      final spyStockRepo = SpyStockInReceiptRepository();
      spyStockRepo.receipts[draftToDelete.id] = draftToDelete;

      final inventorySpy = StrictInventorySpy();
      final productSpy = StrictProductSpy();
      final supplierSpy = StrictSupplierSpy();

      final useCase = DeleteStockInReceiptUseCase(spyStockRepo);

      // Execute draft deletion
      await useCase.execute(
        storeId: 'store_001',
        receipt: draftToDelete,
      );

      // 1. StockInReceiptRepository had exactly 1 deletion call
      expect(spyStockRepo.lastDeletedReceiptId, equals('DRAFT_TO_DELETE_777'));
      expect(spyStockRepo.lastDeletedStoreId, equals('store_001'));
      expect(spyStockRepo.receipts, isEmpty);

      // 2. ProductRepository had ZERO mutation calls (0 branch stock modifications)
      expect(
        productSpy.mutationCallCount,
        equals(0),
        reason:
            'CRITICAL INVARIANT VIOLATION: Deleting draft mutated products!',
      );

      // 3. InventoryRepository had ZERO mutation calls (0 transaction ledger records)
      expect(
        inventorySpy.mutationCallCount,
        equals(0),
        reason:
            'CRITICAL INVARIANT VIOLATION: Deleting draft mutated inventory transactions!',
      );

      // 4. SupplierRepository had ZERO mutation calls (0 debt adjustments)
      expect(
        supplierSpy.mutationCallCount,
        equals(0),
        reason:
            'CRITICAL INVARIANT VIOLATION: Deleting draft mutated supplier debt!',
      );
    });

    test(
        'Illegal Action Defense: Attempting to delete a completed receipt directly throws StateError',
        () async {
      final completedReceipt = StockInReceipt(
        id: 'REC_COMPLETED_PROTECTED',
        importCode: 'PN_PROTECTED',
        status: 'completed',
        date: DateTime.now(),
        storeId: 'store_001',
        items: const [],
      );

      final spyRepo = SpyStockInReceiptRepository();
      final useCase = DeleteStockInReceiptUseCase(spyRepo);

      expect(
        () => useCase.execute(storeId: 'store_001', receipt: completedReceipt),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Không thể xóa phiếu nhập đã hoàn thành'),
          ),
        ),
      );

      // Verify repository was not touched
      expect(spyRepo.lastDeletedReceiptId, isNull);
    });

    testWidgets(
        'Completed and Cancelled cards do NOT expose draft delete button or swipe dismissible',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final completedReceipt = StockInReceipt(
        id: 'rec_safe_c',
        importCode: 'PN_SAFE_C',
        status: 'completed',
        date: DateTime.now(),
        items: const [],
      );

      final cancelledReceipt = StockInReceipt(
        id: 'rec_safe_x',
        importCode: 'PN_SAFE_X',
        status: 'cancelled',
        date: DateTime.now(),
        items: const [],
      );

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([completedReceipt, cancelledReceipt]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // No dismissibles on completed or cancelled cards
      expect(
          find.byKey(const Key('dismissible_draft_rec_safe_c')), findsNothing);
      expect(
          find.byKey(const Key('dismissible_draft_rec_safe_x')), findsNothing);

      // No draft delete icon buttons
      expect(
          find.byKey(const Key('btn_delete_draft_rec_safe_c')), findsNothing);
      expect(
          find.byKey(const Key('btn_delete_draft_rec_safe_x')), findsNothing);
    });

    testWidgets(
        'Direct card delete button (btn_delete_draft_{id}) prompts confirmation dialog and deletes draft',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final spyRepo = SpyStockInReceiptRepository();
      spyRepo.receipts[draftToDelete.id] = draftToDelete;

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptRepositoryProvider.overrideWithValue(spyRepo),
            deleteStockInReceiptUseCaseProvider.overrideWithValue(
              DeleteStockInReceiptUseCase(spyRepo),
            ),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([draftToDelete]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      final deleteBtn = find.byKey(Key('btn_delete_draft_${draftToDelete.id}'));
      expect(deleteBtn, findsOneWidget);

      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      expect(find.text('Xác nhận xóa'), findsOneWidget);
      expect(find.text('Xóa phiếu tạm này?'), findsOneWidget);

      // Confirm
      await tester.tap(find.byKey(const Key('btn_confirm_delete_draft')));
      await tester.pumpAndSettle();

      expect(spyRepo.lastDeletedReceiptId, equals('DRAFT_TO_DELETE_777'));
      expect(spyRepo.receipts.containsKey('DRAFT_TO_DELETE_777'), isFalse);
    });

    testWidgets(
        'Long press on draft card triggers deletion confirmation dialog',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final spyRepo = SpyStockInReceiptRepository();
      spyRepo.receipts[draftToDelete.id] = draftToDelete;

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptRepositoryProvider.overrideWithValue(spyRepo),
            deleteStockInReceiptUseCaseProvider.overrideWithValue(
              DeleteStockInReceiptUseCase(spyRepo),
            ),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([draftToDelete]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Long press card
      await tester.longPress(find.text('#PN_DELETE_777'));
      await tester.pumpAndSettle();

      expect(find.text('Xác nhận xóa'), findsOneWidget);
      expect(find.text('Xóa phiếu tạm này?'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.byKey(const Key('btn_cancel_delete_draft')));
      await tester.pumpAndSettle();

      expect(spyRepo.lastDeletedReceiptId, isNull);
    });

    testWidgets(
        'Network error during draft deletion is caught gracefully and shows error SnackBar',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final throwingRepo = _ThrowingStockInReceiptRepository();

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            deleteStockInReceiptUseCaseProvider.overrideWithValue(
              DeleteStockInReceiptUseCase(throwingRepo),
            ),
            stockInReceiptsProvider.overrideWith(
              (ref) => AsyncValue.data([draftToDelete]),
            ),
          ],
          child: const StockInReceiptsPage(),
        ),
      );
      await tester.pumpAndSettle();

      final deleteBtn = find.byKey(Key('btn_delete_draft_${draftToDelete.id}'));
      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('btn_confirm_delete_draft')));
      await tester.pump(); // Render SnackBar

      expect(find.textContaining('Lỗi khi xóa phiếu tạm:'), findsOneWidget);
    });
  });

  // ==========================================================================
  // SECTION 4: ADVANCED RESUMPTION & EXIT FLOW STRESS TESTS
  // ==========================================================================
  group(
      'Adversarial Dimension 4: Advanced Resumption, AppBar Actions & Exit Dialog',
      () {
    final richDraft = StockInReceipt(
      id: 'DRAFT_ADVANCED_123',
      importCode: 'PN_ADV_123',
      status: 'draft',
      storeId: 'store_001',
      supplierId: 'sup_stress_01',
      date: DateTime.now(),
      items: const [
        StockInReceiptItem(
          transactionId: 'tx_adv_1',
          productId: 'prod_adv_1',
          productName: 'Thuốc bổ não Ginkgo',
          productCode: 'GINKGO',
          quantity: 5,
          importPrice: 80000,
          unit: 'Hộp',
        ),
      ],
    );

    testWidgets(
        'Saving draft via AppBar icon button preserves ID and updates draft',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final spyRepo = SpyStockInReceiptRepository();
      spyRepo.receipts[richDraft.id] = richDraft;

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptRepositoryProvider.overrideWithValue(spyRepo),
            saveStockInDraftUseCaseProvider.overrideWithValue(
              SaveStockInDraftUseCase(spyRepo),
            ),
          ],
          child: ImportInventoryPage(initialReceipt: richDraft),
        ),
      );
      await tester.pumpAndSettle();

      final saveBtn = find.byKey(const Key('btn_save_draft'));
      expect(saveBtn, findsOneWidget);

      await tester.tap(saveBtn);
      await tester.pump();

      expect(spyRepo.lastSavedDraft, isNotNull);
      expect(spyRepo.lastSavedDraft!.id, equals('DRAFT_ADVANCED_123'));
      expect(spyRepo.lastSavedDraft!.importCode, equals('PN_ADV_123'));
      expect(spyRepo.receipts.length, equals(1));
    });

    testWidgets(
        'Exit flow: tapping Close (X) and selecting "Lưu tạm" in StockInExitDialog preserves draft ID and pops',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final spyRepo = SpyStockInReceiptRepository();
      spyRepo.receipts[richDraft.id] = richDraft;

      await tester.pumpWidget(
        _buildChallengerApp(
          overrides: [
            ...baseOverrides,
            stockInReceiptRepositoryProvider.overrideWithValue(spyRepo),
            saveStockInDraftUseCaseProvider.overrideWithValue(
              SaveStockInDraftUseCase(spyRepo),
            ),
          ],
          child: ImportInventoryPage(initialReceipt: richDraft),
        ),
      );
      await tester.pumpAndSettle();

      // Tap close button (Icons.close) in AppBar
      final closeBtn = find.byIcon(Icons.close);
      expect(closeBtn, findsOneWidget);
      await tester.tap(closeBtn);
      await tester.pumpAndSettle();

      // StockInExitDialog appears
      expect(find.byKey(const Key('exit_receipt_dialog')), findsOneWidget);
      expect(find.byKey(const Key('dialog_choice_draft')), findsOneWidget);
      expect(find.byKey(const Key('dialog_choice_stay')), findsOneWidget);
      expect(find.byKey(const Key('dialog_choice_exit')), findsOneWidget);

      // Select "Lưu tạm" in exit dialog
      await tester.tap(find.byKey(const Key('dialog_choice_draft')));
      await tester.pumpAndSettle();

      // Verify draft was saved with identical ID
      expect(spyRepo.lastSavedDraft, isNotNull);
      expect(spyRepo.lastSavedDraft!.id, equals('DRAFT_ADVANCED_123'));
      expect(spyRepo.lastSavedDraft!.importCode, equals('PN_ADV_123'));
      expect(spyRepo.receipts.length, equals(1));
    });

    test(
        'Multi-dimensional search across item SKU, product name, and notes inside mixed receipts',
        () {
      final receiptWithSku = StockInReceipt(
        id: 'r_sku',
        importCode: 'PN_SKU_TEST',
        status: 'draft',
        date: DateTime.now(),
        items: const [
          StockInReceiptItem(
            transactionId: 't1',
            productId: 'p1',
            productCode: 'SPECIFIC_SKU_88',
            productName: 'Thuốc Đặc Trị',
            quantity: 1,
            importPrice: 10000,
          ),
        ],
      );

      final receiptWithNote = StockInReceipt(
        id: 'r_note',
        importCode: 'PN_NOTE_TEST',
        status: 'completed',
        date: DateTime.now(),
        items: const [
          StockInReceiptItem(
            transactionId: 't2',
            productId: 'p2',
            note: 'Hàng nhập lô đặc biệt bảo hành',
            quantity: 1,
            importPrice: 10000,
          ),
        ],
      );

      final allReceipts = [receiptWithSku, receiptWithNote];

      // 1. Search for SKU with status 'draft' -> matches r_sku only
      const filterSkuDraft = StockInReceiptsFilterState(
        searchQuery: 'SPECIFIC_SKU_88',
        statusFilter: 'draft',
      );
      final res1 = filterStockInReceipts(allReceipts, filterSkuDraft);
      expect(res1.length, equals(1));
      expect(res1.first.id, equals('r_sku'));

      // 2. Search for SKU with status 'completed' -> 0 results
      const filterSkuCompleted = StockInReceiptsFilterState(
        searchQuery: 'SPECIFIC_SKU_88',
        statusFilter: 'completed',
      );
      final res2 = filterStockInReceipts(allReceipts, filterSkuCompleted);
      expect(res2, isEmpty);

      // 3. Search for unaccented note "dac biet" with status 'completed' -> matches r_note
      const filterNoteCompleted = StockInReceiptsFilterState(
        searchQuery: 'dac biet',
        statusFilter: 'completed',
      );
      final res3 = filterStockInReceipts(allReceipts, filterNoteCompleted);
      expect(res3.length, equals(1));
      expect(res3.first.id, equals('r_note'));
    });
  });
}

class _ThrowingStockInReceiptRepository extends SpyStockInReceiptRepository {
  @override
  Future<void> deleteReceipt({
    required String storeId,
    required String receiptId,
  }) async {
    throw Exception('Simulated network timeout deleting receipt');
  }
}
