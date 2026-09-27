import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/entities/user_account.dart';

void main() {
  group('StockInReceiptsFilterState & Notifier Tests', () {
    test('default state has thisMonth range, storeId=all, empty query, and 0 active filters', () {
      final state = StockInReceiptsFilterState.defaults();
      expect(state.timeRange, OverviewTimeRange.thisMonth);
      expect(state.customDateRange, isNull);
      expect(state.supplierId, isNull);
      expect(state.storeId, 'all');
      expect(state.searchQuery, '');
      expect(state.hasActiveFilters, isFalse);
      expect(state.activeFilterCount, 0);
    });

    test('activeFilterCount increments as filters deviate from defaults', () {
      var state = StockInReceiptsFilterState.defaults();

      state = state.copyWith(timeRange: OverviewTimeRange.today);
      expect(state.activeFilterCount, 1);
      expect(state.hasActiveFilters, isTrue);

      state = state.copyWith(supplierId: 'NCC001');
      expect(state.activeFilterCount, 2);

      state = state.copyWith(storeId: 'store_002');
      expect(state.activeFilterCount, 3);

      state = state.copyWith(searchQuery: 'sofa');
      expect(state.activeFilterCount, 4);
    });

    test('StockInReceiptsFilterNotifier methods update state correctly', () {
      final notifier = StockInReceiptsFilterNotifier();

      // setTimeRange
      notifier.setTimeRange(OverviewTimeRange.last7Days);
      expect(notifier.state.timeRange, OverviewTimeRange.last7Days);
      expect(notifier.state.customDateRange, isNull);

      // setCustomDateRange
      final custom = DateTimeRange(
        start: DateTime(2026, 9, 1),
        end: DateTime(2026, 9, 15),
      );
      notifier.setCustomDateRange(custom);
      expect(notifier.state.timeRange, OverviewTimeRange.custom);
      expect(notifier.state.customDateRange, custom);

      // setSupplier & setSupplierId
      notifier.setSupplier('NCC002');
      expect(notifier.state.supplierId, 'NCC002');
      notifier.setSupplier('all');
      expect(notifier.state.supplierId, isNull);

      // setStore & setStoreId
      notifier.setStore('store_001');
      expect(notifier.state.storeId, 'store_001');

      // setSearchQuery
      notifier.setSearchQuery('bàn ăn');
      expect(notifier.state.searchQuery, 'bàn ăn');

      // setStatusFilter
      notifier.setStatusFilter('draft');
      expect(notifier.state.statusFilter, 'draft');
      expect(notifier.state.activeFilterCount, greaterThan(0));

      notifier.setStatusFilter('cancelled');
      expect(notifier.state.statusFilter, 'cancelled');

      // resetFilters
      notifier.resetFilters();
      expect(notifier.state.timeRange, OverviewTimeRange.thisMonth);
      expect(notifier.state.supplierId, isNull);
      expect(notifier.state.storeId, 'all');
      expect(notifier.state.searchQuery, '');
      expect(notifier.state.statusFilter, 'all');
    });

    test('StockInReceiptsFilterState toJson and fromJson preserve statusFilter', () {
      final state = StockInReceiptsFilterState.defaults().copyWith(
        statusFilter: 'draft',
        supplierId: 'NCC01',
      );
      final json = state.toJson();
      expect(json['statusFilter'], 'draft');

      final reconstructed = StockInReceiptsFilterState.fromJson(json);
      expect(reconstructed.statusFilter, 'draft');
      expect(reconstructed.supplierId, 'NCC01');
    });
  });

  group('filterStockInReceipts Logic Tests', () {
    final now = DateTime(2026, 9, 21, 11, 30);
    final yesterday = now.subtract(const Duration(days: 1));
    final tenDaysAgo = now.subtract(const Duration(days: 10));

    final r1 = StockInReceipt(
      id: 'r1',
      importCode: 'PN_001',
      date: now,
      storeId: 'store_001',
      supplierId: 'NCC001',
      supplierName: 'Công ty Cổ phần Thế Giới Số (Digiworld)',
      items: const [
        StockInReceiptItem(
          transactionId: 't1',
          productId: 'p1',
          quantity: 2,
          importPrice: 5000000,
          productName: 'Sofa Góc Chữ L Da Bò',
          productCode: 'SF01',
        ),
      ],
    );

    final r2 = StockInReceipt(
      id: 'r2',
      importCode: 'PN_002',
      date: yesterday,
      storeId: 'store_002',
      supplierId: 'NCC002',
      supplierName: 'Công ty TNHH Synnex FPT',
      items: const [
        StockInReceiptItem(
          transactionId: 't2',
          productId: 'p2',
          quantity: 10,
          importPrice: 200000,
          productName: 'Bàn Trà Kính Tròn',
          productCode: 'BT02',
        ),
      ],
    );

    final r3 = StockInReceipt(
      id: 'r3',
      importCode: 'PN_003',
      date: tenDaysAgo,
      storeId: 'store_001',
      supplierId: 'NCC002',
      supplierName: 'Công ty TNHH Synnex FPT',
      items: const [
        StockInReceiptItem(
          transactionId: 't3',
          productId: 'p3',
          quantity: 1,
          importPrice: 12000000,
          productName: 'Giường Ngủ 1m8 Gỗ Gõ Đỏ',
          productCode: 'GN18',
        ),
      ],
    );

    final allReceipts = [r1, r2, r3];

    test('filters by supplierId correctly', () {
      final filter = StockInReceiptsFilterState.defaults().copyWith(
        supplierId: 'NCC001',
      );
      final filtered = filterStockInReceipts(allReceipts, filter);
      expect(filtered.length, 1);
      expect(filtered.first.id, 'r1');
    });

    test('filters by storeId with canonical and legacy name normalization', () {
      // Direct store_002
      final filter1 = StockInReceiptsFilterState.defaults().copyWith(
        storeId: 'store_002',
      );
      final filtered1 = filterStockInReceipts(allReceipts, filter1);
      expect(filtered1.length, 1);
      expect(filtered1.first.id, 'r2');

      // Normalized 'branch_2' -> 'store_002'
      final filter2 = StockInReceiptsFilterState.defaults().copyWith(
        storeId: 'branch_2',
      );
      final filtered2 = filterStockInReceipts(allReceipts, filter2);
      expect(filtered2.length, 1);
      expect(filtered2.first.id, 'r2');
    });

    test('filters by search query on importCode, product SKU, and product name', () {
      // Search by import code
      final fCode = StockInReceiptsFilterState.defaults().copyWith(searchQuery: 'PN_001');
      expect(filterStockInReceipts(allReceipts, fCode).map((e) => e.id), ['r1']);

      // Search by product code SKU
      final fSku = StockInReceiptsFilterState.defaults().copyWith(searchQuery: 'BT02');
      expect(filterStockInReceipts(allReceipts, fSku).map((e) => e.id), ['r2']);

      // Search by product name
      final fName = StockInReceiptsFilterState.defaults().copyWith(searchQuery: 'giường ngủ');
      expect(filterStockInReceipts(allReceipts, fName).map((e) => e.id), ['r3']);
    });

    test('supports unaccented Vietnamese search for supplier name', () {
      // Searching "the gioi so" without accents matches "Công ty Cổ phần Thế Giới Số (Digiworld)"
      final fUnaccented = StockInReceiptsFilterState.defaults().copyWith(
        searchQuery: 'the gioi so',
      );
      final filtered = filterStockInReceipts(allReceipts, fUnaccented);
      expect(filtered.length, 1);
      expect(filtered.first.id, 'r1');
    });

    test('filters by custom date range inclusively', () {
      final filter = StockInReceiptsFilterState.defaults().copyWith(
        timeRange: OverviewTimeRange.custom,
        customDateRange: DateTimeRange(
          start: DateTime(2026, 9, 20),
          end: DateTime(2026, 9, 21),
        ),
      );

      final filtered = filterStockInReceipts(allReceipts, filter);
      // r1 (Sept 21) and r2 (Sept 20) are included; r3 (10 days ago) is excluded
      expect(filtered.length, 2);
      expect(filtered.map((e) => e.id), containsAll(['r1', 'r2']));
      expect(filtered.map((e) => e.id), isNot(contains('r3')));
    });

    test('filters by status correctly for all 3 states: completed, draft, and cancelled', () {
      final now = DateTime(2026, 9, 21);
      final rComp = StockInReceipt(
        id: 'r_comp',
        importCode: 'PN_COMP',
        date: now,
        status: 'Đã hoàn thành',
        items: const [],
      );
      final rDraft = StockInReceipt(
        id: 'r_draft',
        importCode: 'PN_DRAFT',
        date: now,
        status: 'draft',
        items: const [],
      );
      final rCancel = StockInReceipt(
        id: 'r_cancel',
        importCode: 'PN_CANCEL',
        date: now,
        status: 'cancelled',
        items: const [],
      );

      final mixedList = [rComp, rDraft, rCancel];

      // 1. Filter completed
      final fCompleted = StockInReceiptsFilterState.defaults().copyWith(statusFilter: 'completed');
      final completedRes = filterStockInReceipts(mixedList, fCompleted);
      expect(completedRes.length, 1);
      expect(completedRes.first.id, 'r_comp');

      // 2. Filter draft
      final fDraft = StockInReceiptsFilterState.defaults().copyWith(statusFilter: 'draft');
      final draftRes = filterStockInReceipts(mixedList, fDraft);
      expect(draftRes.length, 1);
      expect(draftRes.first.id, 'r_draft');

      // 3. Filter cancelled
      final fCancelled = StockInReceiptsFilterState.defaults().copyWith(statusFilter: 'cancelled');
      final cancelRes = filterStockInReceipts(mixedList, fCancelled);
      expect(cancelRes.length, 1);
      expect(cancelRes.first.id, 'r_cancel');

      // 4. Filter all
      final fAll = StockInReceiptsFilterState.defaults().copyWith(statusFilter: 'all');
      final allRes = filterStockInReceipts(mixedList, fAll);
      expect(allRes.length, 3);
    });
  });

  group('Provider Unit Tests via ProviderContainer', () {
    test('canViewCostPriceProvider returns true for Admin and Supervisor, false for Staff', () {
      // 1. Admin
      final containerAdmin = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => _FakeAuthNotifier(const UserAccount(
              username: 'admin',
              role: 'admin',
              displayName: 'Admin User',
              storeId: 'store_001',
            )),
          ),
        ],
      );
      expect(containerAdmin.read(canViewCostPriceProvider), isTrue);

      // 2. Supervisor
      final containerSupervisor = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => _FakeAuthNotifier(const UserAccount(
              username: 'supervisor',
              role: 'supervisor',
              displayName: 'Supervisor User',
              storeId: 'store_001',
            )),
          ),
        ],
      );
      expect(containerSupervisor.read(canViewCostPriceProvider), isTrue);

      // 3. Staff
      final containerStaff = ProviderContainer(
        overrides: [
          authProvider.overrideWith(
            (ref) => _FakeAuthNotifier(const UserAccount(
              username: 'staff_01',
              role: 'nhanvien',
              displayName: 'Staff User',
              storeId: 'store_001',
            )),
          ),
        ],
      );
      expect(containerStaff.read(canViewCostPriceProvider), isFalse);
    });

    test('stockInReceiptByIdProvider finds receipt by id or importCode', () {
      final now = DateTime(2026, 9, 21);
      final r1 = StockInReceipt(
        id: 'r_target',
        importCode: 'PN_TARGET_123',
        date: now,
        items: const [],
      );

      final container = ProviderContainer(
        overrides: [
          stockInReceiptsProvider.overrideWithValue(AsyncValue.data([r1])),
        ],
      );

      // Lookup by id
      final foundById = container.read(stockInReceiptByIdProvider('r_target'));
      expect(foundById, isNotNull);
      expect(foundById!.importCode, 'PN_TARGET_123');

      // Lookup by importCode
      final foundByCode = container.read(stockInReceiptByIdProvider('PN_TARGET_123'));
      expect(foundByCode, isNotNull);
      expect(foundByCode!.id, 'r_target');

      // Non-existent
      final notFound = container.read(stockInReceiptByIdProvider('PN_NON_EXISTENT'));
      expect(notFound, isNull);
    });

    test('stockInReceiptsProvider merges stored receipts with legacy receipts, stored takes precedence', () async {
      final now = DateTime(2026, 9, 21);
      final legacyTx = InventoryTransaction(
        id: 'legacy_tx_01',
        productId: 'p_shared',
        type: TransactionType.import,
        quantity: 1,
        date: now.subtract(const Duration(hours: 2)),
        note: 'Legacy note',
        importCode: 'PN_SHARED_01',
      );

      final storedDraft = StockInReceipt(
        id: 'stored_draft_01',
        importCode: 'PN_DRAFT_UNIQUE',
        date: now.subtract(const Duration(hours: 1)),
        status: 'draft',
        items: const [],
      );

      final storedOverwrite = StockInReceipt(
        id: 'stored_rec_01',
        importCode: 'PN_SHARED_01', // Same importCode as legacyTx
        date: now,
        status: 'completed',
        note: 'Stored updated note',
        items: const [],
      );

      final container = ProviderContainer(
        overrides: [
          rawImportTransactionsStreamProvider.overrideWith((ref) => Stream.value([legacyTx])),
          storedStockInReceiptsStreamProvider.overrideWith(
            (ref) => Stream.value([storedDraft, storedOverwrite]),
          ),
          allStoresProductsProvider.overrideWith((ref) => Stream.value(<Product>[])),
          allSupplierDebtTransactionsProvider.overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
        ],
      );

      // Await both stream providers to emit their first values
      await container.read(rawImportTransactionsStreamProvider.future);
      await container.read(storedStockInReceiptsStreamProvider.future);

      final asyncValue = container.read(stockInReceiptsProvider);
      expect(asyncValue.hasValue, isTrue);
      final receipts = asyncValue.value!;

      // Both storedDraft and storedOverwrite should be in receipts
      expect(receipts.length, 2);
      expect(receipts.map((e) => e.importCode), containsAll(['PN_DRAFT_UNIQUE', 'PN_SHARED_01']));
      // The receipt with PN_SHARED_01 should be the stored version
      final shared = receipts.firstWhere((r) => r.importCode == 'PN_SHARED_01');
      expect(shared.id, 'stored_rec_01');
      expect(shared.note, 'Stored updated note');
    });

    test('use case providers can be resolved from ProviderContainer', () {
      final container = ProviderContainer(
        overrides: [
          stockInReceiptRepositoryProvider.overrideWithValue(_FakeStockInRepo()),
        ],
      );

      expect(container.read(saveStockInDraftUseCaseProvider), isNotNull);
      expect(container.read(deleteStockInReceiptUseCaseProvider), isNotNull);
    });
  });
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

class _FakeStockInRepo implements StockInReceiptRepository {
  final Map<String, StockInReceipt> receipts = {};

  @override
  Future<String> saveDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
    return receipt.id;
  }

  @override
  Future<void> updateDraft(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteDraft({required String storeId, required String receiptId}) async {
    receipts.remove(receiptId);
  }

  @override
  Future<void> cancelReceipt({
    required String storeId,
    required StockInReceipt receipt,
    required String reason,
    required String cancelledBy,
  }) async {}

  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) =>
      Stream.value(receipts.values.toList());

  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async =>
      receipts.values.toList();

  @override
  Future<StockInReceipt?> getReceiptById({required String storeId, required String receiptId}) async =>
      receipts[receiptId];

  @override
  Future<void> saveReceipt(StockInReceipt receipt) async {
    receipts[receipt.id] = receipt;
  }

  @override
  Future<void> deleteReceipt({required String storeId, required String receiptId}) async {
    receipts.remove(receiptId);
  }

  @override
  Future<double?> getLatestImportPrice({required String storeId, required String productId}) async => null;
}

