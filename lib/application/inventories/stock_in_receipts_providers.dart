import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/filter_storage_service.dart';
import '../../core/utils/store_resolver_helper.dart';
import '../../core/utils/vietnamese_text_helper.dart';
import '../../data/datasources/firebase/inventory_remote_data_source.dart';
import '../../data/datasources/stock_in_receipt_remote_data_source.dart';
import '../../data/repositories/inventory_repository_impl.dart';
import '../../data/repositories/stock_in_receipt_repository_impl.dart';
import '../../domain/entities/inventory_transaction.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/stock_in_receipt.dart';
import '../../domain/entities/supplier_debt_transaction.dart';
import '../../domain/repositories/product_repository.dart';
import '../../domain/repositories/stock_in_receipt_repository.dart';
import '../auth/auth_providers.dart';
import '../inventory/inventory_providers.dart';
import '../products/products_providers.dart';
import '../reports/overview_providers.dart';
import '../suppliers/suppliers_providers.dart';
import 'usecases/cancel_stock_in_receipt_use_case.dart';
import 'usecases/complete_stock_in_receipt_use_case.dart';
import 'usecases/delete_stock_in_receipt_use_case.dart';
import 'usecases/save_stock_in_draft_use_case.dart';

export '../../data/datasources/stock_in_receipt_remote_data_source.dart';
export '../../domain/entities/stock_in_receipt.dart';
export '../../domain/repositories/stock_in_receipt_repository.dart';
export 'usecases/cancel_stock_in_receipt_use_case.dart';
export 'usecases/complete_stock_in_receipt_use_case.dart';
export 'usecases/delete_stock_in_receipt_use_case.dart';
export 'usecases/save_stock_in_draft_use_case.dart';

/// Immutable filter state for Stock-in Receipts (Phiếu nhập kho).
class StockInReceiptsFilterState {
  final OverviewTimeRange timeRange;
  final DateTimeRange? customDateRange;
  final String? supplierId; // null or 'all' = all suppliers
  final String? storeId; // null or 'all' = all stores, or specific store ID
  final String searchQuery;
  final String statusFilter; // 'all', 'completed', 'draft', 'cancelled'

  const StockInReceiptsFilterState({
    this.timeRange = OverviewTimeRange.thisMonth,
    this.customDateRange,
    this.supplierId,
    this.storeId = 'all',
    this.searchQuery = '',
    this.statusFilter = 'all',
  });

  factory StockInReceiptsFilterState.defaults() {
    return const StockInReceiptsFilterState(
      timeRange: OverviewTimeRange.thisMonth,
      customDateRange: null,
      supplierId: null,
      storeId: 'all',
      searchQuery: '',
      statusFilter: 'all',
    );
  }

  bool get hasActiveFilters => activeFilterCount > 0;

  int get activeFilterCount {
    int count = 0;
    if (timeRange != OverviewTimeRange.thisMonth) count++;
    if (supplierId != null && supplierId!.isNotEmpty && supplierId != 'all')
      count++;
    if (storeId != null && storeId!.isNotEmpty && storeId != 'all') count++;
    if (searchQuery.trim().isNotEmpty) count++;
    if (statusFilter != 'all') count++;
    return count;
  }

  StockInReceiptsFilterState copyWith({
    OverviewTimeRange? timeRange,
    DateTimeRange? customDateRange,
    bool clearCustomDateRange = false,
    String? supplierId,
    bool clearSupplierId = false,
    String? storeId,
    bool clearStoreId = false,
    String? searchQuery,
    String? statusFilter,
  }) {
    return StockInReceiptsFilterState(
      timeRange: timeRange ?? this.timeRange,
      customDateRange: clearCustomDateRange
          ? null
          : (customDateRange ?? this.customDateRange),
      supplierId: clearSupplierId ? null : (supplierId ?? this.supplierId),
      storeId: clearStoreId ? null : (storeId ?? this.storeId),
      searchQuery: searchQuery ?? this.searchQuery,
      statusFilter: statusFilter ?? this.statusFilter,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'timeRange': timeRange.name,
        'customStartDate': customDateRange?.start.toIso8601String(),
        'customEndDate': customDateRange?.end.toIso8601String(),
        'supplierId': supplierId,
        'storeId': storeId,
        'statusFilter': statusFilter,
      };

  factory StockInReceiptsFilterState.fromJson(Map<String, dynamic> json) {
    OverviewTimeRange range = OverviewTimeRange.thisMonth;
    if (json['timeRange'] != null) {
      try {
        range = OverviewTimeRange.values.byName(json['timeRange'].toString());
      } catch (_) {
        range = OverviewTimeRange.thisMonth;
      }
    }

    DateTimeRange? custom;
    if (json['customStartDate'] != null && json['customEndDate'] != null) {
      final start = DateTime.tryParse(json['customStartDate'].toString());
      final end = DateTime.tryParse(json['customEndDate'].toString());
      if (start != null && end != null) {
        custom = DateTimeRange(start: start, end: end);
      }
    }

    return StockInReceiptsFilterState(
      timeRange: range,
      customDateRange: custom,
      supplierId: json['supplierId']?.toString(),
      storeId: json['storeId']?.toString() ?? 'all',
      searchQuery: '',
      statusFilter: json['statusFilter']?.toString() ?? 'all',
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StockInReceiptsFilterState &&
          runtimeType == other.runtimeType &&
          timeRange == other.timeRange &&
          customDateRange == other.customDateRange &&
          supplierId == other.supplierId &&
          storeId == other.storeId &&
          searchQuery == other.searchQuery &&
          statusFilter == other.statusFilter;

  @override
  int get hashCode =>
      timeRange.hashCode ^
      (customDateRange?.hashCode ?? 0) ^
      (supplierId?.hashCode ?? 0) ^
      (storeId?.hashCode ?? 0) ^
      searchQuery.hashCode ^
      statusFilter.hashCode;

  @override
  String toString() {
    return 'StockInReceiptsFilterState(range: ${timeRange.name}, supplier: $supplierId, store: $storeId, query: "$searchQuery", status: $statusFilter)';
  }
}

/// StateNotifier managing [StockInReceiptsFilterState] with automatic persistence and store-locking.
class StockInReceiptsFilterNotifier
    extends StateNotifier<StockInReceiptsFilterState> {
  final Ref? _ref;

  StockInReceiptsFilterNotifier([this._ref])
      : super(StockInReceiptsFilterState.defaults()) {
    _hydrate();
  }

  void _hydrate() {
    if (_ref == null) return;
    try {
      final user = _ref.watch(authProvider);
      if (user != null) {
        final storage = _ref.watch(filterStorageServiceProvider);
        final saved =
            storage.loadFilterSync('stock_in_receipts', user.username);
        if (saved != null) {
          state = StockInReceiptsFilterState.fromJson(saved);
        }
        // If staff, lock store selection to assigned storeId
        if (!user.canSwitchStore && user.storeId.isNotEmpty) {
          state = state.copyWith(storeId: user.storeId);
        }
      }
    } catch (_) {}
  }

  void _persist() {
    if (_ref == null) return;
    try {
      final user = _ref.read(authProvider);
      if (user != null) {
        final storage = _ref.read(filterStorageServiceProvider);
        storage.saveFilter('stock_in_receipts', state.toJson(), user.username);
      }
    } catch (_) {}
  }

  /// Sets the predefined time range.
  void setTimeRange(OverviewTimeRange range) {
    if (range != OverviewTimeRange.custom) {
      state = state.copyWith(timeRange: range, clearCustomDateRange: true);
    } else {
      state = state.copyWith(timeRange: range);
    }
    _persist();
  }

  /// Alias for [setTimeRange].
  void setTimeRangeType(OverviewTimeRange range) => setTimeRange(range);

  /// Sets custom date range and updates timeRange to custom.
  void setCustomDateRange(DateTimeRange range) {
    state = state.copyWith(
      timeRange: OverviewTimeRange.custom,
      customDateRange: range,
    );
    _persist();
  }

  /// Filters by supplier ID or clears supplier filter when null/'all'.
  void setSupplier(String? supplierId) {
    final effective =
        (supplierId == null || supplierId.trim().isEmpty || supplierId == 'all')
            ? null
            : supplierId.trim();
    state = state.copyWith(
      supplierId: effective,
      clearSupplierId: effective == null,
    );
    _persist();
  }

  /// Alias for [setSupplier].
  void setSupplierId(String? supplierId) => setSupplier(supplierId);

  /// Filters by store ID or sets to 'all'.
  void setStore(String? storeId) {
    final effective =
        (storeId == null || storeId.trim().isEmpty) ? 'all' : storeId.trim();
    state = state.copyWith(storeId: effective);
    _persist();
  }

  /// Alias for [setStore].
  void setStoreId(String? storeId) => setStore(storeId);

  /// Updates text search query (searches across import code, supplier name, product name/SKU).
  void setSearchQuery(String query) {
    state = state.copyWith(searchQuery: query);
  }

  /// Filters by status: 'all', 'completed', 'draft', 'cancelled'.
  void setStatusFilter(String status) {
    final effective =
        status.trim().isEmpty ? 'all' : status.trim().toLowerCase();
    state = state.copyWith(statusFilter: effective);
    _persist();
  }

  /// Resets all filter dimensions back to standard defaults.
  void resetFilters() {
    String? lockedStoreId;
    if (_ref != null) {
      try {
        final user = _ref.read(authProvider);
        if (user != null && !user.canSwitchStore && user.storeId.isNotEmpty) {
          lockedStoreId = user.storeId;
        }
      } catch (_) {}
    }
    state = StockInReceiptsFilterState.defaults().copyWith(
      storeId: lockedStoreId,
    );
    _persist();
  }

  /// Alias for [resetFilters].
  void reset() => resetFilters();
}

/// Auto-disposed provider managing stock-in receipts filter state.
final stockInReceiptsFilterProvider = StateNotifierProvider.autoDispose<
    StockInReceiptsFilterNotifier, StockInReceiptsFilterState>((ref) {
  return StockInReceiptsFilterNotifier(ref);
});

/// Streams raw [InventoryTransaction] of type `import` across target stores
/// resolved by [StoreResolverHelper.resolveTargetStoreIds].
final rawImportTransactionsStreamProvider =
    StreamProvider.autoDispose<List<InventoryTransaction>>((ref) {
  final filter = ref.watch(stockInReceiptsFilterProvider);
  final user = ref.watch(authProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final availableStores = ref.watch(availableStoresProvider).valueOrNull ?? {};

  final targetStoreIds = StoreResolverHelper.resolveTargetStoreIds(
    [],
    currentStoreId: currentStoreId,
    user: user,
    storeFilter: filter.storeId,
    availableStores: availableStores,
  );

  if (targetStoreIds.isEmpty) {
    return Stream.value(<InventoryTransaction>[]);
  }

  DateTimeRange range;
  if (filter.timeRange == OverviewTimeRange.custom &&
      filter.customDateRange != null) {
    range = filter.customDateRange!;
  } else {
    range = filter.timeRange.getRange();
  }

  DateTime effectiveEnd = range.end;
  if (effectiveEnd.hour == 0 &&
      effectiveEnd.minute == 0 &&
      effectiveEnd.second == 0) {
    effectiveEnd = DateTime(effectiveEnd.year, effectiveEnd.month,
        effectiveEnd.day, 23, 59, 59, 999);
  }

  return _createCombinedImportTransactionsStream(
      targetStoreIds, range.start, effectiveEnd, ref);
});

/// Alias provider for [rawImportTransactionsStreamProvider].
final rawImportTransactionsProvider = rawImportTransactionsStreamProvider;

/// Combines import transactions streams across multiple store branches.
Stream<List<InventoryTransaction>> _createCombinedImportTransactionsStream(
  List<String> storeIds,
  DateTime startDate,
  DateTime endDate,
  Ref ref,
) {
  final controller = StreamController<List<InventoryTransaction>>();
  final Map<String, List<InventoryTransaction>> storeDataMap = {};
  final List<StreamSubscription> subs = [];

  FirebaseDatabase? db;
  try {
    db = FirebaseDatabase.instance;
  } catch (_) {
    // Firebase not initialized in pure unit test environments
  }

  if (db == null) {
    try {
      final repo = ref.watch(inventoryRepositoryProvider);
      final sub = repo.watchImportsByDateRange(startDate, endDate).listen(
        (items) {
          if (!controller.isClosed) controller.add(items);
        },
        onError: (_) {},
      );
      subs.add(sub);
    } catch (_) {}
  } else {
    for (final storeId in storeIds) {
      final ds = InventoryRemoteDataSource(db, storeId);
      final repo = InventoryRepositoryImpl(ds);

      final sub = repo.watchImportsByDateRange(startDate, endDate).listen(
        (items) {
          storeDataMap[storeId] = items;
          final combined = storeDataMap.values.expand((e) => e).toList();
          combined.sort((a, b) => b.date.compareTo(a.date));
          if (!controller.isClosed) {
            controller.add(combined);
          }
        },
        onError: (_) {},
      );
      subs.add(sub);
    }
  }

  void cleanup() {
    for (final s in subs) {
      s.cancel();
    }
    subs.clear();
    if (!controller.isClosed) {
      controller.close();
    }
  }

  controller.onCancel = cleanup;
  ref.onDispose(cleanup);

  return controller.stream;
}

/// Provider streaming all supplier debt transactions across known suppliers.
final allSupplierDebtTransactionsProvider =
    StreamProvider.autoDispose<List<SupplierDebtTransaction>>((ref) {
  final suppliersAsync = ref.watch(supplierListNotifierProvider);
  final suppliers = suppliersAsync.value ?? [];
  if (suppliers.isEmpty) {
    return Stream.value(<SupplierDebtTransaction>[]);
  }

  final controller = StreamController<List<SupplierDebtTransaction>>();
  final Map<String, List<SupplierDebtTransaction>> debtsBySupplier = {};
  final List<StreamSubscription> subs = [];
  final repo = ref.watch(supplierRepositoryProvider);
  final storeId = ref.watch(currentStoreIdProvider);

  for (final supplier in suppliers) {
    final sub =
        repo.watchDebtTransactions(supplier.id, storeId: storeId).listen(
      (debts) {
        debtsBySupplier[supplier.id] = debts;
        final allDebts = debtsBySupplier.values.expand((e) => e).toList();
        if (!controller.isClosed) {
          controller.add(allDebts);
        }
      },
      onError: (_) {},
    );
    subs.add(sub);
  }

  void cleanup() {
    for (final s in subs) {
      s.cancel();
    }
    subs.clear();
    if (!controller.isClosed) {
      controller.close();
    }
  }

  controller.onCancel = cleanup;
  ref.onDispose(cleanup);

  return controller.stream;
});

/// Remote data source provider for stock-in receipts.
final stockInReceiptRemoteDataSourceProvider =
    Provider.autoDispose<StockInReceiptRemoteDataSource>((ref) {
  FirebaseDatabase? db;
  try {
    db = FirebaseDatabase.instance;
  } catch (_) {}
  return StockInReceiptRemoteDataSource(db ?? FirebaseDatabase.instance);
});

/// Repository provider for stock-in receipts.
final stockInReceiptRepositoryProvider =
    Provider.autoDispose<StockInReceiptRepository>((ref) {
  final ds = ref.watch(stockInReceiptRemoteDataSourceProvider);
  ProductRepository? productRepo;
  try {
    productRepo = ref.watch(productRepositoryProvider);
  } catch (_) {}
  return StockInReceiptRepositoryImpl(ds, productRepository: productRepo);
});

/// Use case provider for saving drafts.
final saveStockInDraftUseCaseProvider =
    Provider.autoDispose<SaveStockInDraftUseCase>((ref) {
  final repo = ref.watch(stockInReceiptRepositoryProvider);
  return SaveStockInDraftUseCase(repo);
});

/// Use case provider for completing receipts.
final completeStockInReceiptUseCaseProvider =
    Provider.autoDispose<CompleteStockInReceiptUseCase>((ref) {
  FirebaseDatabase? db;
  try {
    db = FirebaseDatabase.instance;
  } catch (_) {}
  return CompleteStockInReceiptUseCase(
    db: db,
    productRepository: ref.watch(productRepositoryProvider),
    inventoryRepository: ref.watch(inventoryRepositoryProvider),
    supplierRepository: ref.watch(supplierRepositoryProvider),
    receiptRepository: ref.watch(stockInReceiptRepositoryProvider),
  );
});

/// Use case provider for cancelling receipts.
final cancelStockInReceiptUseCaseProvider =
    Provider.autoDispose<CancelStockInReceiptUseCase>((ref) {
  FirebaseDatabase? db;
  try {
    db = FirebaseDatabase.instance;
  } catch (_) {}
  return CancelStockInReceiptUseCase(
    db: db,
    productRepository: ref.watch(productRepositoryProvider),
    inventoryRepository: ref.watch(inventoryRepositoryProvider),
    supplierRepository: ref.watch(supplierRepositoryProvider),
    receiptRepository: ref.watch(stockInReceiptRepositoryProvider),
  );
});

/// Use case provider for deleting receipts/drafts.
final deleteStockInReceiptUseCaseProvider =
    Provider.autoDispose<DeleteStockInReceiptUseCase>((ref) {
  final repo = ref.watch(stockInReceiptRepositoryProvider);
  return DeleteStockInReceiptUseCase(repo);
});

/// Real-time stream of stored stock-in receipts from RTDB path `stores/$storeId/stock_in_receipts`.
final storedStockInReceiptsStreamProvider =
    StreamProvider.autoDispose<List<StockInReceipt>>((ref) {
  final filter = ref.watch(stockInReceiptsFilterProvider);
  final user = ref.watch(authProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final availableStores = ref.watch(availableStoresProvider).valueOrNull ?? {};

  final targetStoreIds = StoreResolverHelper.resolveTargetStoreIds(
    [],
    currentStoreId: currentStoreId,
    user: user,
    storeFilter: filter.storeId,
    availableStores: availableStores,
  );

  if (targetStoreIds.isEmpty) {
    return Stream.value(<StockInReceipt>[]);
  }

  return _createCombinedStoredReceiptsStream(targetStoreIds, ref);
});

Stream<List<StockInReceipt>> _createCombinedStoredReceiptsStream(
  List<String> storeIds,
  Ref ref,
) {
  final controller = StreamController<List<StockInReceipt>>();
  final Map<String, List<StockInReceipt>> storeDataMap = {};
  final List<StreamSubscription> subs = [];

  FirebaseDatabase? db;
  try {
    db = FirebaseDatabase.instance;
  } catch (_) {}

  if (db == null) {
    if (!controller.isClosed) {
      controller.add([]);
    }
  } else {
    try {
      final repo = ref.watch(stockInReceiptRepositoryProvider);
      for (final sId in storeIds) {
        final sub = repo.watchReceipts(sId).listen(
          (items) {
            storeDataMap[sId] = items;
            final combined = storeDataMap.values.expand((e) => e).toList();
            combined.sort((a, b) => b.date.compareTo(a.date));
            if (!controller.isClosed) {
              controller.add(combined);
            }
          },
          onError: (_) {},
        );
        subs.add(sub);
      }
    } catch (_) {
      if (!controller.isClosed) {
        controller.add([]);
      }
    }
  }

  void cleanup() {
    for (final s in subs) {
      s.cancel();
    }
    subs.clear();
    if (!controller.isClosed) {
      controller.close();
    }
  }

  controller.onCancel = cleanup;
  ref.onDispose(cleanup);

  return controller.stream;
}

/// Auto-disposed provider combining stored RTDB receipts and legacy import transactions
/// into consolidated [StockInReceipt] entities. Stored receipts take precedence.
final stockInReceiptsProvider =
    Provider.autoDispose<AsyncValue<List<StockInReceipt>>>((ref) {
  final txAsync = ref.watch(rawImportTransactionsStreamProvider);
  final storedAsync = ref.watch(storedStockInReceiptsStreamProvider);

  // Products lookup
  AsyncValue<List<Product>> productsAsync;
  try {
    productsAsync = ref.watch(allStoresProductsProvider);
  } catch (_) {
    productsAsync = ref.watch(productListProvider);
  }

  final debtAsync = ref.watch(allSupplierDebtTransactionsProvider);

  if (txAsync.isLoading && storedAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (txAsync.hasError && storedAsync.hasError) {
    return AsyncValue.error(txAsync.error!, txAsync.stackTrace!);
  }

  final transactions = txAsync.value ?? const [];
  final storedReceipts = storedAsync.value ?? const [];
  final products = productsAsync.value ?? const [];
  final debts = debtAsync.value ?? const [];

  final legacyReceipts = groupTransactionsToReceipts(
    transactions: transactions,
    products: products,
    debtTransactions: debts,
  );

  // Merge: Stored receipts overwrite legacy grouped receipts with matching importCode / ID
  final Map<String, StockInReceipt> receiptsByKey = {};
  final Map<String, String> codeToIdMap = {};

  for (final legacy in legacyReceipts) {
    receiptsByKey[legacy.id] = legacy;
    if (legacy.importCode.isNotEmpty) {
      codeToIdMap[legacy.importCode] = legacy.id;
    }
  }

  for (final stored in storedReceipts) {
    if (stored.importCode.isNotEmpty &&
        codeToIdMap.containsKey(stored.importCode)) {
      final oldId = codeToIdMap[stored.importCode]!;
      receiptsByKey.remove(oldId);
    }
    receiptsByKey[stored.id] = stored;
    if (stored.importCode.isNotEmpty) {
      codeToIdMap[stored.importCode] = stored.id;
    }
  }

  final List<StockInReceipt> merged = receiptsByKey.values.toList();
  merged.sort((a, b) => b.date.compareTo(a.date));

  return AsyncValue.data(merged);
});

/// Synchronous list provider extracting receipts from [stockInReceiptsProvider].
final stockInReceiptsListProvider =
    Provider.autoDispose<List<StockInReceipt>>((ref) {
  final asyncVal = ref.watch(stockInReceiptsProvider);
  return asyncVal.value ?? const [];
});

/// Provider filtering receipts by [StockInReceiptsFilterState]
/// (Date range, Supplier, Branch, and Search query). Returns [List<StockInReceipt>].
final filteredStockInReceiptsProvider =
    Provider.autoDispose<List<StockInReceipt>>((ref) {
  final receipts = ref.watch(stockInReceiptsListProvider);
  final filter = ref.watch(stockInReceiptsFilterProvider);
  return filterStockInReceipts(receipts, filter);
});

/// AsyncValue variant of filtered receipts for reactive UI states (`when(data, loading, error)`).
final filteredStockInReceiptsAsyncProvider =
    Provider.autoDispose<AsyncValue<List<StockInReceipt>>>((ref) {
  final receiptsAsync = ref.watch(stockInReceiptsProvider);
  final filter = ref.watch(stockInReceiptsFilterProvider);
  return receiptsAsync
      .whenData((receipts) => filterStockInReceipts(receipts, filter));
});

/// Provider retrieving a single [StockInReceipt] by its `id` or `importCode`.
final stockInReceiptByIdProvider =
    Provider.autoDispose.family<StockInReceipt?, String>((ref, idOrCode) {
  final receipts = ref.watch(stockInReceiptsListProvider);
  final target = idOrCode.trim();
  for (final r in receipts) {
    if (r.id == target || r.importCode == target) {
      return r;
    }
  }
  return null;
});

/// Provider indicating whether current user has permission to view cost prices and monetary totals.
final canViewCostPriceProvider = Provider.autoDispose<bool>((ref) {
  final user = ref.watch(authProvider);
  return user?.canViewCostPrice ?? false;
});

/// Pure helper function to filter a list of [StockInReceipt] by [StockInReceiptsFilterState].
List<StockInReceipt> filterStockInReceipts(
  List<StockInReceipt> receipts,
  StockInReceiptsFilterState filter,
) {
  if (receipts.isEmpty) return const [];

  DateTimeRange range;
  if (filter.timeRange == OverviewTimeRange.custom &&
      filter.customDateRange != null) {
    range = filter.customDateRange!;
  } else {
    range = filter.timeRange.getRange();
  }

  DateTime effectiveEnd = range.end;
  if (effectiveEnd.hour == 0 &&
      effectiveEnd.minute == 0 &&
      effectiveEnd.second == 0) {
    effectiveEnd = DateTime(effectiveEnd.year, effectiveEnd.month,
        effectiveEnd.day, 23, 59, 59, 999);
  }

  final filterSupplier = (filter.supplierId != null &&
          filter.supplierId!.isNotEmpty &&
          filter.supplierId != 'all')
      ? filter.supplierId
      : null;

  final filterStore = (filter.storeId != null &&
          filter.storeId!.isNotEmpty &&
          filter.storeId != 'all')
      ? StoreResolverHelper.normalizeStoreId(filter.storeId)
      : null;

  final trimmedQuery = filter.searchQuery.trim();
  final hasQuery = trimmedQuery.isNotEmpty;
  final queryLower = trimmedQuery.toLowerCase();
  final queryNorm =
      hasQuery ? VietnameseTextHelper.normalizeUnaccented(trimmedQuery) : '';

  return receipts.where((receipt) {
    // 1. Date Range Check
    if (receipt.date.isBefore(range.start) ||
        receipt.date.isAfter(effectiveEnd)) {
      return false;
    }

    // 2. Supplier Check
    if (filterSupplier != null) {
      if (receipt.supplierId != filterSupplier) {
        return false;
      }
    }

    // 3. Store Check
    if (filterStore != null) {
      final receiptStore =
          StoreResolverHelper.normalizeStoreId(receipt.storeId);
      if (receiptStore != filterStore) {
        return false;
      }
    }

    // 4. Search Query Check
    if (hasQuery) {
      if (!_matchesReceiptSearch(receipt, queryLower, queryNorm)) {
        return false;
      }
    }

    // 5. Status Filter Check
    if (filter.statusFilter != 'all') {
      final s = filter.statusFilter.toLowerCase();
      if (s == 'draft' || s == 'phieu_tam' || s == 'phiếu tạm') {
        if (!receipt.isDraft) return false;
      } else if (s == 'cancelled' || s == 'da_huy' || s == 'đã hủy') {
        if (!receipt.isCancelled) return false;
      } else if (s == 'completed' ||
          s == 'da_hoan_thanh' ||
          s == 'đã hoàn thành') {
        if (!receipt.isCompleted) return false;
      }
    }

    return true;
  }).toList();
}

bool _matchesReceiptSearch(
    StockInReceipt receipt, String queryLower, String queryNorm) {
  // Check importCode
  if (receipt.importCode.toLowerCase().contains(queryLower)) return true;

  // Check supplierName
  if (receipt.supplierName != null && receipt.supplierName!.isNotEmpty) {
    if (receipt.supplierName!.toLowerCase().contains(queryLower)) return true;
    final supNorm =
        VietnameseTextHelper.normalizeUnaccented(receipt.supplierName!);
    if (supNorm.contains(queryNorm)) return true;
  }

  // Check items (productCode, productName, note)
  for (final item in receipt.items) {
    if (item.productCode != null && item.productCode!.isNotEmpty) {
      if (item.productCode!.toLowerCase().contains(queryLower)) return true;
    }
    if (item.productName != null && item.productName!.isNotEmpty) {
      if (item.productName!.toLowerCase().contains(queryLower)) return true;
      final nameNorm =
          VietnameseTextHelper.normalizeUnaccented(item.productName!);
      if (nameNorm.contains(queryNorm)) return true;
    }
    if (item.note.isNotEmpty) {
      if (item.note.toLowerCase().contains(queryLower)) return true;
      final noteNorm = VietnameseTextHelper.normalizeUnaccented(item.note);
      if (noteNorm.contains(queryNorm)) return true;
    }
  }

  // Check receipt note
  if (receipt.note.isNotEmpty) {
    if (receipt.note.toLowerCase().contains(queryLower)) return true;
    final rNoteNorm = VietnameseTextHelper.normalizeUnaccented(receipt.note);
    if (rNoteNorm.contains(queryNorm)) return true;
  }

  return false;
}
