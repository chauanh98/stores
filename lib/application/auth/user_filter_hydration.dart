import 'package:flutter/material.dart';

import '../../core/services/filter_storage_service.dart';
import '../../domain/entities/user_account.dart';
import '../../presentation/orders/controllers/invoices_filter_controller.dart';
import '../customers/customers_providers.dart';
import '../orders/cart_providers.dart';
import '../products/products_providers.dart';
import '../reports/overview_providers.dart';
import 'auth_providers.dart';

/// Centralized rehydration of all user filters across Overview, Invoices,
/// Customers, Products, and Selected Store upon successful authentication.
Future<void> rehydrateAllUserFilters(
  dynamic ref,
  UserAccount user, [
  String? Function()? getCurrentUsername,
]) async {
  final storage =
      ref.read(filterStorageServiceProvider) as FilterStorageService;

  bool isUserActive() {
    if (getCurrentUsername != null) {
      return getCurrentUsername() == user.username;
    }
    try {
      return (ref.read(authProvider) as UserAccount?)?.username ==
          user.username;
    } catch (_) {
      return true;
    }
  }

  if (!isUserActive()) {
    return;
  }

  // 0. POS branch preference hydration for admin / supervisor
  try {
    if (user.isAdmin || user.isSupervisor || user.canSwitchStore) {
      final savedStore = await storage.loadSelectedStore(user.username);
      if (isUserActive() &&
          savedStore != null &&
          savedStore.isNotEmpty &&
          savedStore != 'all') {
        ref.read(selectedPOSBranchProvider.notifier).state = savedStore;
      }
    }
  } catch (_) {}

  if (!isUserActive()) {
    return;
  }

  // 1. Overview filters
  try {
    final overviewData = await storage.loadFilter('overview', user.username);
    if (!isUserActive()) {
      return;
    }
    if (overviewData != null) {
      if (overviewData['timeRangeType'] != null) {
        try {
          final type = OverviewTimeRange.values
              .byName(overviewData['timeRangeType']?.toString() ?? '');
          ref.read(overviewTimeRangeTypeProvider.notifier).state = type;
        } catch (_) {}
      }
      if (overviewData['customStartDate'] != null &&
          overviewData['customEndDate'] != null) {
        final start = DateTime.tryParse(
            overviewData['customStartDate']?.toString() ?? '');
        final end =
            DateTime.tryParse(overviewData['customEndDate']?.toString() ?? '');
        if (start != null && end != null) {
          ref.read(overviewCustomDateRangeProvider.notifier).state =
              DateTimeRange(start: start, end: end);
        }
      }
      if (overviewData.containsKey('selectedStoreFilter')) {
        final storeFilter = overviewData['selectedStoreFilter'];
        ref.read(selectedStoreFilterProvider.notifier).state =
            storeFilter is String ? storeFilter : (storeFilter?.toString());
      }
      if (overviewData['selectedBranches'] is List) {
        final branches = (overviewData['selectedBranches'] as List)
            .map((e) => e.toString())
            .where((id) => id.isNotEmpty)
            .toList();
        if (branches.isNotEmpty) {
          ref
              .read(selectedBranchesProvider.notifier)
              .setBranches(branches, persist: false);
        }
      }
    }
  } catch (_) {}

  if (!isUserActive()) {
    return;
  }

  // 2. Invoices filters
  try {
    final invoicesData = await storage.loadFilter('invoices', user.username);
    if (!isUserActive()) {
      return;
    }
    if (invoicesData != null) {
      final hydrated = InvoicesFilterState.fromJson(invoicesData);
      ref.read(invoicesFilterProvider.notifier).setHydratedState(hydrated);
    }
  } catch (_) {}

  if (!isUserActive()) {
    return;
  }

  // 3. Customers filters
  try {
    if (!user.canViewDebtSummary) {
      ref.read(customerDebtFilterProvider.notifier).state =
          CustomerDebtFilter.all;
    }
    final customersData = await storage.loadFilter('customers', user.username);
    if (!isUserActive()) {
      return;
    }
    if (customersData != null) {
      if (user.canViewDebtSummary && customersData['debtFilter'] != null) {
        final debt = CustomerDebtFilter.values.firstWhere(
          (e) => e.name == customersData['debtFilter']?.toString(),
          orElse: () => CustomerDebtFilter.all,
        );
        ref.read(customerDebtFilterProvider.notifier).state = debt;
      }
      if (customersData.containsKey('timeRangeType')) {
        final rawType = customersData['timeRangeType'];
        if (rawType == null) {
          ref.read(customerTimeRangeTypeProvider.notifier).state = null;
        } else {
          try {
            final timeRange =
                OverviewTimeRange.values.byName(rawType.toString());
            ref.read(customerTimeRangeTypeProvider.notifier).state = timeRange;
          } catch (_) {}
        }
      }
      if (customersData['customStartDate'] != null &&
          customersData['customEndDate'] != null) {
        final start = DateTime.tryParse(
            customersData['customStartDate']?.toString() ?? '');
        final end =
            DateTime.tryParse(customersData['customEndDate']?.toString() ?? '');
        if (start != null && end != null) {
          ref.read(customerCustomDateRangeProvider.notifier).state =
              DateTimeRange(start: start, end: end);
        }
      }
    }
  } catch (_) {}

  if (!isUserActive()) {
    return;
  }

  // 4. Products filters
  try {
    final productsData = await storage.loadFilter('products', user.username);
    if (!isUserActive()) {
      return;
    }
    if (productsData != null) {
      if (productsData['selectedCategories'] is List) {
        final cats = (productsData['selectedCategories'] as List)
            .map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty && e != 'null' && e != 'All')
            .toSet();
        ref.read(productSelectedCategoriesProvider.notifier).state = cats;
        if (cats.isNotEmpty) {
          ref.read(productCategoryFilterProvider.notifier).state =
              cats.length == 1 ? cats.first : 'All';
        } else {
          ref.read(productCategoryFilterProvider.notifier).state = 'All';
        }
      } else if (productsData['category'] != null) {
        final cat = productsData['category'].toString().trim();
        ref.read(productCategoryFilterProvider.notifier).state = cat;
        if (cat.isNotEmpty && cat != 'null' && cat != 'All') {
          ref.read(productSelectedCategoriesProvider.notifier).state = {cat};
        } else {
          ref.read(productSelectedCategoriesProvider.notifier).state =
              const <String>{};
        }
      }
      if (productsData['productTypes'] is List) {
        final types = (productsData['productTypes'] as List)
            .map((e) => e.toString())
            .map((name) =>
                ProductTypeFilter.values.cast<ProductTypeFilter?>().firstWhere(
                      (v) => v?.name == name,
                      orElse: () => null,
                    ))
            .whereType<ProductTypeFilter>()
            .toSet();
        if (types.isNotEmpty) {
          ref.read(productTypeFilterProvider.notifier).state = types;
        }
      }
      if (productsData['stockStatus'] != null) {
        final status = StockStatus.values.firstWhere(
          (e) => e.name == productsData['stockStatus']?.toString(),
          orElse: () => StockStatus.all,
        );
        ref.read(productStockStatusFilterProvider.notifier).state = status;
      }
    }
  } catch (_) {}
}

/// Resets all in-memory filter providers to default states without deleting disk caches.
void resetAllInMemoryFilters(dynamic ref) {
  try {
    MultiCartNotifier.resetBranchCartsCache();
    ref.read(branchCartsCacheProvider.notifier).state =
        <String, MultiCartState>{};
    ref.read(overviewTimeRangeTypeProvider.notifier).state =
        OverviewTimeRange.today;
    ref.read(overviewCustomDateRangeProvider.notifier).state =
        OverviewTimeRange.today.getRange();
    ref.read(selectedBranchesProvider.notifier).selectAll(persist: false);
    ref.read(selectedStoreFilterProvider.notifier).state = null;
    ref.read(invoicesFilterProvider.notifier).resetInMemory();
    ref.read(customerDebtFilterProvider.notifier).state =
        CustomerDebtFilter.all;
    ref.read(customerTimeRangeTypeProvider.notifier).state = null;
    ref.read(customerCustomDateRangeProvider.notifier).state =
        OverviewTimeRange.thisMonth.getRange();
    ref.read(productCategoryFilterProvider.notifier).state = 'All';
    ref.read(productSelectedCategoriesProvider.notifier).state =
        const <String>{};
    ref.read(productTypeFilterProvider.notifier).state = const {
      ProductTypeFilter.standard,
      ProductTypeFilter.combo,
      ProductTypeFilter.service,
    };
    ref.read(productStockStatusFilterProvider.notifier).state = StockStatus.all;
    ref.read(productBrandFilterProvider.notifier).state = null;
    ref.read(productSortOptionProvider.notifier).state =
        ProductSortOption.stockDesc;
    ref.read(selectedStoreIdProvider.notifier).state = null;
    ref.invalidate(selectedPOSBranchProvider);
  } catch (_) {}
}
