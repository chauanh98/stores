import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/data/repositories/stock_in_receipt_repository_impl.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/repositories/product_repository.dart';

import '../support/firebase_test_harness.dart';

class _FakeProductRepo implements ProductRepository {
  final Map<String, Product> products = {};

  void add(Product p) => products[p.id] = p;

  @override
  Future<Product?> fetchById(String id) async => products[id];

  @override
  Future<List<Product>> fetchAll() async => products.values.toList();

  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());

  @override
  Future<void> upsert(Product product) async => products[product.id] = product;

  @override
  Future<void> delete(String id) async => products.remove(id);

  @override
  Future<void> updateStock(String id, int newStock) async {}
}

void main() {
  group('Milestone 1 Challenger Suite: 3-State Filtering, Dedup & Latest Price', () {
    // =========================================================================
    // 1. 3-STATE FILTERING STRESS TESTS
    // =========================================================================
    group('1. 3-State Status Filtering & Mixed Streams', () {
      final baseDate = DateTime(2026, 9, 21, 10, 0);

      // Create a heterogeneous set of receipts with various status encodings
      final rCompletedExplicit = StockInReceipt(
        id: 'r_comp_1',
        importCode: 'PN_COMP_1',
        date: baseDate,
        status: 'completed',
        items: const [],
      );

      final rCompletedVietnamese = StockInReceipt(
        id: 'r_comp_2',
        importCode: 'PN_COMP_2',
        date: baseDate.add(const Duration(minutes: 5)),
        status: 'Đã hoàn thành',
        items: const [],
      );

      final rDraftExplicit = StockInReceipt(
        id: 'r_draft_1',
        importCode: 'PN_DRAFT_1',
        date: baseDate.add(const Duration(minutes: 10)),
        status: 'draft',
        items: const [],
      );

      final rDraftVietnamese = StockInReceipt(
        id: 'r_draft_2',
        importCode: 'PN_DRAFT_2',
        date: baseDate.add(const Duration(minutes: 15)),
        status: 'Phiếu tạm',
        items: const [],
      );

      final rCancelledExplicit = StockInReceipt(
        id: 'r_cancel_1',
        importCode: 'PN_CANCEL_1',
        date: baseDate.add(const Duration(minutes: 20)),
        status: 'cancelled',
        items: const [],
      );

      final rCancelledVietnamese = StockInReceipt(
        id: 'r_cancel_2',
        importCode: 'PN_CANCEL_2',
        date: baseDate.add(const Duration(minutes: 25)),
        status: 'Đã hủy',
        items: const [],
      );

      // Legacy transaction groups (un-statused, default 'Đã nhập hàng')
      final rLegacyImported = StockInReceipt(
        id: 'r_legacy_1',
        importCode: 'PN_LEGACY_1',
        date: baseDate.add(const Duration(minutes: 30)),
        status: 'Đã nhập hàng',
        items: const [],
      );

      // Arbitrary legacy status string
      final rLegacyCustom = StockInReceipt(
        id: 'r_legacy_2',
        importCode: 'PN_LEGACY_2',
        date: baseDate.add(const Duration(minutes: 35)),
        status: 'imported',
        items: const [],
      );

      final allSampleReceipts = [
        rCompletedExplicit,
        rCompletedVietnamese,
        rDraftExplicit,
        rDraftVietnamese,
        rCancelledExplicit,
        rCancelledVietnamese,
        rLegacyImported,
        rLegacyCustom,
      ];

      test('statusFilter = "all" preserves all receipts without omission', () {
        final filter = StockInReceiptsFilterState.defaults().copyWith(
          timeRange: OverviewTimeRange.thisMonth,
          statusFilter: 'all',
        );

        final result = filterStockInReceipts(allSampleReceipts, filter);
        expect(result.length, 8);
        expect(result.map((r) => r.id), containsAll(allSampleReceipts.map((r) => r.id)));
      });

      test('statusFilter = "completed" matches explicit completed AND legacy un-statused, but strictly excludes drafts and cancelled', () {
        for (final alias in ['completed', 'da_hoan_thanh', 'đã hoàn thành', 'COMPLETED']) {
          final filter = StockInReceiptsFilterState.defaults().copyWith(statusFilter: alias);
          final result = filterStockInReceipts(allSampleReceipts, filter);

          // Should match: rCompletedExplicit, rCompletedVietnamese, rLegacyImported, rLegacyCustom
          expect(result.length, 4, reason: 'Failed for status alias: $alias');
          expect(result.map((r) => r.id), containsAll(['r_comp_1', 'r_comp_2', 'r_legacy_1', 'r_legacy_2']));
          expect(result.any((r) => r.isDraft), isFalse);
          expect(result.any((r) => r.isCancelled), isFalse);
          for (final r in result) {
            expect(r.isCompleted, isTrue);
          }
        }
      });

      test('statusFilter = "draft" matches ONLY draft receipts ("draft", "Phiếu tạm"), never completed, legacy, or cancelled', () {
        for (final alias in ['draft', 'phieu_tam', 'phiếu tạm', 'DRAFT']) {
          final filter = StockInReceiptsFilterState.defaults().copyWith(statusFilter: alias);
          final result = filterStockInReceipts(allSampleReceipts, filter);

          expect(result.length, 2, reason: 'Failed for status alias: $alias');
          expect(result.map((r) => r.id), containsAll(['r_draft_1', 'r_draft_2']));
          for (final r in result) {
            expect(r.isDraft, isTrue);
            expect(r.isCompleted, isFalse);
            expect(r.isCancelled, isFalse);
          }
        }
      });

      test('statusFilter = "cancelled" matches ONLY cancelled receipts ("cancelled", "Đã hủy"), never completed or drafts', () {
        for (final alias in ['cancelled', 'da_huy', 'đã hủy', 'CANCELLED']) {
          final filter = StockInReceiptsFilterState.defaults().copyWith(statusFilter: alias);
          final result = filterStockInReceipts(allSampleReceipts, filter);

          expect(result.length, 2, reason: 'Failed for status alias: $alias');
          expect(result.map((r) => r.id), containsAll(['r_cancel_1', 'r_cancel_2']));
          for (final r in result) {
            expect(r.isCancelled, isTrue);
            expect(r.isDraft, isFalse);
            expect(r.isCompleted, isFalse);
          }
        }
      });

      test('Massive Mixed Stream (120 Receipts): partition completeness and mutual exclusivity', () {
        final List<StockInReceipt> massiveStream = [];
        final streamBase = DateTime(2026, 9, 21);

        for (int i = 0; i < 120; i++) {
          String status;
          if (i < 40) {
            status = i.isEven ? 'completed' : 'Đã hoàn thành';
          } else if (i < 70) {
            status = i.isEven ? 'draft' : 'Phiếu tạm';
          } else if (i < 90) {
            status = i.isEven ? 'cancelled' : 'Đã hủy';
          } else {
            status = i.isEven ? 'Đã nhập hàng' : 'legacy_tx';
          }

          massiveStream.add(StockInReceipt(
            id: 'rec_$i',
            importCode: 'PN_${i.toString().padLeft(4, '0')}',
            date: streamBase.add(Duration(minutes: i)),
            status: status,
            items: const [],
          ));
        }

        final fDraft = StockInReceiptsFilterState.defaults().copyWith(statusFilter: 'draft');
        final fCancelled = StockInReceiptsFilterState.defaults().copyWith(statusFilter: 'cancelled');
        final fCompleted = StockInReceiptsFilterState.defaults().copyWith(statusFilter: 'completed');
        final fAll = StockInReceiptsFilterState.defaults().copyWith(statusFilter: 'all');

        final drafts = filterStockInReceipts(massiveStream, fDraft);
        final cancelled = filterStockInReceipts(massiveStream, fCancelled);
        final completed = filterStockInReceipts(massiveStream, fCompleted);
        final all = filterStockInReceipts(massiveStream, fAll);

        expect(drafts.length, 30);
        expect(cancelled.length, 20);
        expect(completed.length, 70); // 40 explicit + 30 legacy
        expect(all.length, 120);

        // Verification of mutual exclusivity
        final draftIds = drafts.map((e) => e.id).toSet();
        final cancelIds = cancelled.map((e) => e.id).toSet();
        final compIds = completed.map((e) => e.id).toSet();

        expect(draftIds.intersection(cancelIds), isEmpty);
        expect(draftIds.intersection(compIds), isEmpty);
        expect(cancelIds.intersection(compIds), isEmpty);
        expect(draftIds.union(cancelIds).union(compIds).length, 120);
      });

      test('Compound Filtering: Status Filter + Date Range Boundary Stress', () {
        final start = DateTime(2026, 9, 10, 0, 0, 0);
        final end = DateTime(2026, 9, 20, 23, 59, 59, 999);
        final customRange = DateTimeRange(start: start, end: end);

        final rBeforeRange = StockInReceipt(
          id: 'r_before',
          importCode: 'PN_BEFORE',
          date: start.subtract(const Duration(milliseconds: 1)),
          status: 'draft',
          items: const [],
        );

        final rAtStart = StockInReceipt(
          id: 'r_at_start',
          importCode: 'PN_START',
          date: start,
          status: 'draft',
          items: const [],
        );

        final rMiddleDraft = StockInReceipt(
          id: 'r_mid_draft',
          importCode: 'PN_MID_DRAFT',
          date: DateTime(2026, 9, 15, 12, 0),
          status: 'draft',
          items: const [],
        );

        final rMiddleCompleted = StockInReceipt(
          id: 'r_mid_comp',
          importCode: 'PN_MID_COMP',
          date: DateTime(2026, 9, 15, 12, 0),
          status: 'completed',
          items: const [],
        );

        final rAtEnd = StockInReceipt(
          id: 'r_at_end',
          importCode: 'PN_END',
          date: end,
          status: 'draft',
          items: const [],
        );

        final rAfterRange = StockInReceipt(
          id: 'r_after',
          importCode: 'PN_AFTER',
          date: end.add(const Duration(milliseconds: 1)),
          status: 'draft',
          items: const [],
        );

        final boundaryList = [
          rBeforeRange,
          rAtStart,
          rMiddleDraft,
          rMiddleCompleted,
          rAtEnd,
          rAfterRange,
        ];

        final filter = StockInReceiptsFilterState.defaults().copyWith(
          timeRange: OverviewTimeRange.custom,
          customDateRange: customRange,
          statusFilter: 'draft',
        );

        final result = filterStockInReceipts(boundaryList, filter);

        // Expected matches: rAtStart, rMiddleDraft, rAtEnd
        // Excluded: rBeforeRange (outside date), rAfterRange (outside date), rMiddleCompleted (non-matching status)
        expect(result.length, 3);
        expect(result.map((r) => r.id), containsAll(['r_at_start', 'r_mid_draft', 'r_at_end']));
        expect(result.map((r) => r.id), isNot(contains('r_before')));
        expect(result.map((r) => r.id), isNot(contains('r_after')));
        expect(result.map((r) => r.id), isNot(contains('r_mid_comp')));
      });

      test('Compound Multi-dimensional Filtering (Status + Store + Supplier + Search)', () {
        final targetReceipt = StockInReceipt(
          id: 'r_target_all',
          importCode: 'PN_TARGET_VIP',
          date: DateTime(2026, 9, 21, 14, 0),
          storeId: 'store_001',
          supplierId: 'NCC_VINAGRO',
          supplierName: 'Công ty Cổ phần Phân bón Vinagro',
          status: 'draft',
          items: const [
            StockInReceiptItem(
              transactionId: 't1',
              productId: 'p_phan_bon',
              productName: 'Phân Bón NPK Cao Cấp 20-20-15',
              productCode: 'NPK-20-15',
              quantity: 50,
              importPrice: 450000,
            ),
          ],
        );

        final distractors = [
          targetReceipt.copyWith(id: 'd1', status: 'completed'), // Wrong status
          targetReceipt.copyWith(id: 'd2', storeId: 'store_002'), // Wrong store
          targetReceipt.copyWith(id: 'd3', supplierId: 'NCC_OTHER'), // Wrong supplier
          targetReceipt.copyWith(
            id: 'd4',
            importCode: 'PN_OTHER',
            items: const [
              StockInReceiptItem(
                transactionId: 't2',
                productId: 'p_sofa',
                productName: 'Bàn Trà Mặt Kính',
                productCode: 'BT-01',
                quantity: 1,
                importPrice: 100000,
              ),
            ],
          ), // Wrong query
        ];

        final fullList = [targetReceipt, ...distractors];

        // Search with unaccented Vietnamese "phan bon npk"
        final filter = StockInReceiptsFilterState.defaults().copyWith(
          statusFilter: 'draft',
          storeId: 'store_001',
          supplierId: 'NCC_VINAGRO',
          searchQuery: 'phan bon npk',
        );

        final result = filterStockInReceipts(fullList, filter);
        expect(result.length, 1);
        expect(result.first.id, 'r_target_all');
      });

      test('StockInReceiptsFilterNotifier dynamically updates status and resets cleanly', () {
        final notifier = StockInReceiptsFilterNotifier();

        expect(notifier.state.statusFilter, 'all');

        notifier.setStatusFilter('draft');
        expect(notifier.state.statusFilter, 'draft');

        notifier.setStatusFilter('cancelled');
        expect(notifier.state.statusFilter, 'cancelled');

        notifier.setStatusFilter('completed');
        expect(notifier.state.statusFilter, 'completed');

        // Whitespace and empty fallback
        notifier.setStatusFilter('   ');
        expect(notifier.state.statusFilter, 'all');

        // Reset
        notifier.setStatusFilter('draft');
        notifier.resetFilters();
        expect(notifier.state.statusFilter, 'all');
      });
    });

    // =========================================================================
    // 2. GET LATEST IMPORT PRICE LOOKUP STRESS TESTS
    // =========================================================================
    group('2. getLatestImportPrice Empirical Stress Tests', () {
      late MockFirebaseDatabase mockDb;
      late StockInReceiptRemoteDataSource remoteDs;
      late _FakeProductRepo productRepo;
      late StockInReceiptRepositoryImpl repository;

      const storeId = 'store_001';

      setUp(() {
        mockDb = MockFirebaseDatabase();
        remoteDs = StockInReceiptRemoteDataSource(mockDb);
        productRepo = _FakeProductRepo();
        repository = StockInReceiptRepositoryImpl(remoteDs, productRepository: productRepo);
      });

      test('Multiple historical transactions out of chronological order: returns purchase price corresponding to latest date', () async {
        const prodId = 'PROD_HISTORICAL';

        // Seed 5 historical transactions with deliberately shuffled dates
        mockDb.seedData('stores/$storeId/inventory_transactions', {
          'tx_1': {
            'id': 'tx_1',
            'productId': prodId,
            'type': 'import',
            'importPrice': 100000.0,
            'date': '2026-01-15T08:00:00.000Z',
          },
          'tx_2': {
            'id': 'tx_2',
            'productId': prodId,
            'type': 'import',
            'importPrice': 555000.0, // HIGHEST PRICE, but older date
            'date': '2026-05-10T09:00:00.000Z',
          },
          'tx_3': {
            'id': 'tx_3',
            'productId': prodId,
            'type': 'import',
            'importPrice': 320000.0, // LATEST DATE (2026-09-25)
            'date': '2026-09-25T14:30:00.000Z',
          },
          'tx_4': {
            'id': 'tx_4',
            'productId': prodId,
            'type': 'import',
            'importPrice': 200000.0,
            'date': '2026-03-20T10:00:00.000Z',
          },
          'tx_5': {
            'id': 'tx_5',
            'productId': prodId,
            'type': 'import',
            'importPrice': 290000.0,
            'date': '2026-08-01T11:00:00.000Z',
          },
        });

        // Also add catalog costPrice to verify transaction price takes precedence
        productRepo.add(const Product(
          id: prodId,
          code: 'HIST',
          name: 'Sản phẩm thử nghiệm lịch sử giá',
          price: 150000.0,
          costPrice: 88888.0,
          branchStocks: {'store_001': 10},
          category: 'General',
        ));

        final latestPrice = await repository.getLatestImportPrice(
          storeId: storeId,
          productId: prodId,
        );

        expect(latestPrice, isNotNull);
        expect(latestPrice, 320000.0, reason: 'Must pick latest transaction by date (2026-09-25)');
      });

      test('Filters out non-import transactions and zero/negative prices, selecting genuine latest import', () async {
        const prodId = 'PROD_FILTER_TX';

        mockDb.seedData('stores/$storeId/inventory_transactions', {
          'tx_export': {
            'id': 'tx_export',
            'productId': prodId,
            'type': 'export',
            'importPrice': 999000.0, // Newest date, but type is export
            'date': '2026-09-26T10:00:00.000Z',
          },
          'tx_audit': {
            'id': 'tx_audit',
            'productId': prodId,
            'type': 'inventoryAudit',
            'importPrice': 888000.0,
            'date': '2026-09-24T10:00:00.000Z',
          },
          'tx_zero_price': {
            'id': 'tx_zero_price',
            'productId': prodId,
            'type': 'import',
            'importPrice': 0.0, // Zero price invalid
            'date': '2026-09-23T10:00:00.000Z',
          },
          'tx_negative_price': {
            'id': 'tx_negative_price',
            'productId': prodId,
            'type': 'import',
            'importPrice': -50000.0, // Negative price invalid
            'date': '2026-09-22T10:00:00.000Z',
          },
          'tx_valid_latest': {
            'id': 'tx_valid_latest',
            'productId': prodId,
            'type': 'import',
            'importPrice': 275000.0, // Genuine latest valid import
            'date': '2026-09-20T10:00:00.000Z',
          },
          'tx_valid_older': {
            'id': 'tx_valid_older',
            'productId': prodId,
            'type': 'import',
            'importPrice': 250000.0,
            'date': '2026-09-10T10:00:00.000Z',
          },
        });

        final latestPrice = await repository.getLatestImportPrice(
          storeId: storeId,
          productId: prodId,
        );

        expect(latestPrice, 275000.0);
      });

      test('Fallback to Product.costPrice when no transactions exist for product', () async {
        const prodId = 'PROD_NO_TX';

        // Catalog has product with costPrice = 175,000 VND
        productRepo.add(const Product(
          id: prodId,
          code: 'NOTX',
          name: 'Hàng mới chưa từng nhập kho',
          price: 250000.0,
          costPrice: 175000.0,
          branchStocks: {'store_001': 0},
          category: 'General',
        ));

        final latestPrice = await repository.getLatestImportPrice(
          storeId: storeId,
          productId: prodId,
        );

        expect(latestPrice, 175000.0);
      });

      test('Returns null when no transactions exist and product costPrice is 0 or negative', () async {
        const prodIdZero = 'PROD_ZERO_COST';
        productRepo.add(const Product(
          id: prodIdZero,
          code: 'ZERO',
          name: 'Hàng giá vốn 0',
          price: 50000.0,
          costPrice: 0.0,
          branchStocks: {'store_001': 5},
          category: 'General',
        ));

        final priceZero = await repository.getLatestImportPrice(
          storeId: storeId,
          productId: prodIdZero,
        );
        expect(priceZero, isNull);

        // Completely non-existent product
        final priceGhost = await repository.getLatestImportPrice(
          storeId: storeId,
          productId: 'PROD_NON_EXISTENT',
        );
        expect(priceGhost, isNull);
      });

      test('Store branch isolation: distinct branches return their respective latest prices without leakage', () async {
        const prodId = 'PROD_SHARED_BRANCH';

        // Branch 1 transactions
        mockDb.seedData('stores/store_001/inventory_transactions', {
          'tx_b1': {
            'id': 'tx_b1',
            'productId': prodId,
            'type': 'import',
            'importPrice': 110000.0,
            'date': '2026-09-20T10:00:00.000Z',
          },
        });

        // Branch 2 transactions
        mockDb.seedData('stores/store_002/inventory_transactions', {
          'tx_b2': {
            'id': 'tx_b2',
            'productId': prodId,
            'type': 'import',
            'importPrice': 195000.0,
            'date': '2026-09-25T10:00:00.000Z',
          },
        });

        final priceBranch1 = await repository.getLatestImportPrice(
          storeId: 'store_001',
          productId: prodId,
        );
        final priceBranch2 = await repository.getLatestImportPrice(
          storeId: 'store_002',
          productId: prodId,
        );

        expect(priceBranch1, 110000.0);
        expect(priceBranch2, 195000.0);
      });
    });

    // =========================================================================
    // 3. PROVIDER DEDUPLICATION & STORED RECEIPT PRECEDENCE STRESS TESTS
    // =========================================================================
    group('3. Provider Deduplication & RTDB Precedence', () {
      final now = DateTime(2026, 9, 21, 12, 0);

      test('Collision on importCode: RTDB stored receipt strictly supersedes legacy grouped receipt', () async {
        const sharedCode = 'PN_COLLISION_01';

        // Legacy stream has import transactions with sharedCode
        final legacyTx1 = InventoryTransaction(
          id: 'tx_legacy_part1',
          productId: 'p_wheat',
          type: TransactionType.import,
          quantity: 10,
          importPrice: 100000,
          date: now.subtract(const Duration(hours: 3)),
          note: 'Legacy import part 1',
          importCode: sharedCode,
        );
        final legacyTx2 = InventoryTransaction(
          id: 'tx_legacy_part2',
          productId: 'p_corn',
          type: TransactionType.import,
          quantity: 5,
          importPrice: 200000,
          date: now.subtract(const Duration(hours: 3)),
          note: 'Legacy import part 2',
          importCode: sharedCode,
        );

        // RTDB stored receipt with different ID but SAME importCode
        final storedReceipt = StockInReceipt(
          id: 'stored_unique_id_999',
          importCode: sharedCode,
          date: now,
          status: 'cancelled',
          cancelReason: 'Nhập nhầm nhà cung cấp - Đã hủy',
          cancelledBy: 'admin',
          note: 'Ghi chú cập nhật từ RTDB',
          items: const [
            StockInReceiptItem(
              transactionId: 'stored_item_1',
              productId: 'p_wheat',
              quantity: 10,
              importPrice: 100000,
            ),
          ],
        );

        final container = ProviderContainer(
          overrides: [
            rawImportTransactionsStreamProvider.overrideWith((ref) => Stream.value([legacyTx1, legacyTx2])),
            storedStockInReceiptsStreamProvider.overrideWith((ref) => Stream.value([storedReceipt])),
            allStoresProductsProvider.overrideWith((ref) => Stream.value(<Product>[])),
            allSupplierDebtTransactionsProvider.overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
          ],
        );

        // Await stream emissions
        await container.read(rawImportTransactionsStreamProvider.future);
        await container.read(storedStockInReceiptsStreamProvider.future);

        final receiptsAsync = container.read(stockInReceiptsProvider);
        expect(receiptsAsync.hasValue, isTrue);
        final receipts = receiptsAsync.value!;

        // Deduplication check: EXACTLY ONE receipt with sharedCode
        final matching = receipts.where((r) => r.importCode == sharedCode).toList();
        expect(matching.length, 1, reason: 'Duplicate receipt with importCode $sharedCode was not deduplicated!');

        final resultReceipt = matching.first;
        expect(resultReceipt.id, 'stored_unique_id_999');
        expect(resultReceipt.status, 'cancelled');
        expect(resultReceipt.isCancelled, isTrue);
        expect(resultReceipt.cancelReason, 'Nhập nhầm nhà cung cấp - Đã hủy');
        expect(resultReceipt.note, 'Ghi chú cập nhật từ RTDB');
        expect(resultReceipt.itemCount, 1);
      });

      test('Stored draft takes precedence over legacy grouped transaction, rendering receipt as editable draft', () async {
        const draftCode = 'PN_DRAFT_OVER_LEGACY';

        final legacyTx = InventoryTransaction(
          id: 'tx_old',
          productId: 'p1',
          type: TransactionType.import,
          quantity: 2,
          importPrice: 500000,
          date: now.subtract(const Duration(days: 1)),
          note: 'Legacy import tx',
          importCode: draftCode,
        );

        final storedDraft = StockInReceipt(
          id: 'draft_rec_id',
          importCode: draftCode,
          date: now,
          status: 'draft',
          items: const [],
        );

        final container = ProviderContainer(
          overrides: [
            rawImportTransactionsStreamProvider.overrideWith((ref) => Stream.value([legacyTx])),
            storedStockInReceiptsStreamProvider.overrideWith((ref) => Stream.value([storedDraft])),
            allStoresProductsProvider.overrideWith((ref) => Stream.value(<Product>[])),
            allSupplierDebtTransactionsProvider.overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
          ],
        );

        await container.read(rawImportTransactionsStreamProvider.future);
        await container.read(storedStockInReceiptsStreamProvider.future);

        final receipts = container.read(stockInReceiptsProvider).value!;
        expect(receipts.length, 1);
        expect(receipts.first.id, 'draft_rec_id');
        expect(receipts.first.isDraft, isTrue);
        expect(receipts.first.isCompleted, isFalse);
      });

      test('Massive Collision Benchmark: 50 Legacy + 50 Stored with 25 Overlaps yields exactly 75 deduplicated receipts in descending order', () async {
        final List<InventoryTransaction> legacyTxs = [];
        final List<StockInReceipt> storedReceipts = [];

        // 50 Legacy transactions: PN_000 to PN_049
        for (int i = 0; i < 50; i++) {
          final code = 'PN_${i.toString().padLeft(3, '0')}';
          legacyTxs.add(InventoryTransaction(
            id: 'legacy_tx_$i',
            productId: 'p_$i',
            type: TransactionType.import,
            quantity: 1,
            importPrice: 100000.0,
            date: now.subtract(Duration(hours: i + 50)),
            note: 'Legacy transaction #$i',
            importCode: code,
          ));
        }

        // 50 Stored receipts: PN_025 to PN_074 (25 overlap with legacy PN_025..PN_049, 25 new PN_050..PN_074)
        for (int i = 25; i < 75; i++) {
          final code = 'PN_${i.toString().padLeft(3, '0')}';
          storedReceipts.add(StockInReceipt(
            id: 'stored_rec_$i',
            importCode: code,
            date: now.subtract(Duration(hours: i)),
            status: i % 2 == 0 ? 'completed' : 'draft',
            note: 'Stored note #$i',
            items: const [],
          ));
        }

        final container = ProviderContainer(
          overrides: [
            rawImportTransactionsStreamProvider.overrideWith((ref) => Stream.value(legacyTxs)),
            storedStockInReceiptsStreamProvider.overrideWith((ref) => Stream.value(storedReceipts)),
            allStoresProductsProvider.overrideWith((ref) => Stream.value(<Product>[])),
            allSupplierDebtTransactionsProvider.overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
          ],
        );

        await container.read(rawImportTransactionsStreamProvider.future);
        await container.read(storedStockInReceiptsStreamProvider.future);

        final merged = container.read(stockInReceiptsProvider).value!;

        // 50 legacy + 50 stored - 25 duplicates = 75 total receipts
        expect(merged.length, 75);

        // Check that all 25 overlapping codes are the stored versions
        for (int i = 25; i < 50; i++) {
          final code = 'PN_${i.toString().padLeft(3, '0')}';
          final found = merged.firstWhere((r) => r.importCode == code);
          expect(found.id, 'stored_rec_$i', reason: 'Stored receipt did not take precedence for $code');
          expect(found.note, 'Stored note #$i');
        }

        // Verify strictly descending chronological order
        for (int i = 0; i < merged.length - 1; i++) {
          final currDate = merged[i].date;
          final nextDate = merged[i + 1].date;
          expect(
            currDate.isAfter(nextDate) || currDate.isAtSameMomentAs(nextDate),
            isTrue,
            reason: 'Merged receipts are not sorted descending: index $i ($currDate) vs index ${i + 1} ($nextDate)',
          );
        }
      });
    });
  });
}
