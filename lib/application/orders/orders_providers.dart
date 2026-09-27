import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/store_resolver_helper.dart';
import '../../core/utils/stream_debounce_helper.dart';
import '../../data/datasources/firebase/order_remote_data_source.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../domain/entities/order.dart';
import '../../domain/entities/return_order.dart';
import '../../domain/repositories/order_repository.dart';
import '../auth/auth_providers.dart';
import '../reports/overview_providers.dart';

import '../customers/customers_providers.dart';
import '../inventory/inventory_providers.dart';
import '../products/products_providers.dart';
import 'usecases/cancel_invoice_usecase.dart';
import 'usecases/collect_invoice_debt_usecase.dart';
import 'usecases/process_return_order_usecase.dart';

final firebaseDatabaseProvider = Provider<FirebaseDatabase>((ref) {
  return FirebaseDatabase.instance;
});

final orderRemoteDataSourceProvider = Provider<OrderRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  final db = ref.watch(firebaseDatabaseProvider);
  return OrderRemoteDataSource(db, storeId);
});

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final ds = ref.watch(orderRemoteDataSourceProvider);
  return OrderRepositoryImpl(ds);
});

final processReturnOrderUseCaseProvider =
    Provider<ProcessReturnOrderUseCase>((ref) {
  return ProcessReturnOrderUseCase(
    orderRepository: ref.watch(orderRepositoryProvider),
    productRepository: ref.watch(productRepositoryProvider),
    inventoryRepository: ref.watch(inventoryRepositoryProvider),
    customerRepository: ref.watch(customerRepositoryProvider),
    customerDataSource: ref.watch(customerRemoteDataSourceProvider),
  );
});

final collectInvoiceDebtUseCaseProvider =
    Provider<CollectInvoiceDebtUseCase>((ref) {
  return CollectInvoiceDebtUseCase(
    orderRepository: ref.watch(orderRepositoryProvider),
    customerRepository: ref.watch(customerRepositoryProvider),
    customerDataSource: ref.watch(customerRemoteDataSourceProvider),
  );
});

final cancelInvoiceUseCaseProvider = Provider<CancelInvoiceUseCase>((ref) {
  return CancelInvoiceUseCase(
    orderRepository: ref.watch(orderRepositoryProvider),
    productRepository: ref.watch(productRepositoryProvider),
    inventoryRepository: ref.watch(inventoryRepositoryProvider),
    customerRepository: ref.watch(customerRepositoryProvider),
    customerDataSource: ref.watch(customerRemoteDataSourceProvider),
  );
});

final customerOrdersProvider =
    StreamProvider.autoDispose.family<List<Order>, String>((ref, customerId) {
  final user = ref.watch(authProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final availableStores = ref.watch(availableStoresProvider).valueOrNull ?? {};

  final isAdmin = user?.canSwitchStore == true || user?.isAdmin == true;

  final List<String> targetStoreIds;
  if (isAdmin) {
    final stores = availableStores.keys
        .map(StoreResolverHelper.normalizeStoreId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    targetStoreIds =
        stores.isNotEmpty ? stores : const ['store_001', 'store_002'];
  } else {
    final staffStore =
        (user != null && user.storeId.isNotEmpty && user.storeId != 'all')
            ? user.storeId
            : (currentStoreId.isNotEmpty ? currentStoreId : 'store_001');
    final normalized = StoreResolverHelper.normalizeStoreId(staffStore);
    targetStoreIds = [normalized.isNotEmpty ? normalized : staffStore];
  }

  if (targetStoreIds.isEmpty) {
    return Stream.value(<Order>[]);
  }

  final db = ref.watch(firebaseDatabaseProvider);
  return _createCombinedCustomerOrdersStream(
    ref,
    customerId,
    targetStoreIds,
    database: db,
  );
});

Stream<List<Order>> _createCombinedCustomerOrdersStream(
  Ref ref,
  String customerId,
  List<String> targetStoreIds, {
  FirebaseDatabase? database,
}) {
  if (targetStoreIds.isEmpty) {
    return Stream.value(<Order>[]);
  }

  // ignore: close_sinks
  final controller = StreamController<List<Order>>();
  final Map<String, List<Order>> storeOrdersMap = {};
  final List<StreamSubscription> subs = [];
  final FirebaseDatabase db = database ?? FirebaseDatabase.instance;

  for (final storeId in targetStoreIds) {
    final ds = OrderRemoteDataSource(db, storeId);
    final repo = OrderRepositoryImpl(ds);

    final sub = repo.watchByCustomer(customerId).listen(
      (orders) {
        final enrichedOrders = orders.map((o) {
          if (o.storeId == null || o.storeId!.isEmpty) {
            return o.copyWith(storeId: storeId);
          }
          return o;
        }).toList();

        storeOrdersMap[storeId] = enrichedOrders;
        final combined = storeOrdersMap.values.expand((e) => e).toList();
        combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        if (!controller.isClosed) {
          controller.add(combined);
        }
      },
      onError: (e) {
        debugPrint('Error watching customer orders for store $storeId: $e');
      },
    );
    subs.add(sub);
  }

  void cleanup() {
    for (final sub in subs) {
      sub.cancel();
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

// allOrdersProvider đã bị xóa vì không được dùng ở đâu
// và tạo listener .onValue trên TOÀN BỘ node orders - rất lãng phí bandwidth

final ordersByDateRangeProvider =
    StreamProvider.autoDispose.family<List<Order>, DateTimeRange>((ref, range) {
  return ref
      .watch(orderRepositoryProvider)
      .watchByDateRange(range.start, range.end);
});

final allBranchesOrdersByDateRangeProvider =
    StreamProvider.autoDispose.family<List<Order>, DateTimeRange>((ref, range) {
  final user = ref.watch(authProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final selectedBranches = ref.watch(selectedBranchesProvider);
  final availableStores = ref.watch(availableStoresProvider).valueOrNull ?? {};

  final targetStoreIds = StoreResolverHelper.resolveTargetStoreIds(
    selectedBranches,
    currentStoreId: currentStoreId,
    user: user,
    availableStores: availableStores,
  );

  if (targetStoreIds.isEmpty) {
    return Stream.value(<Order>[]);
  }

  return _createCombinedOrdersStream(targetStoreIds, range);
});

Stream<List<Order>> _createCombinedOrdersStream(
    List<String> storeIds, DateTimeRange range) {
  // ignore: close_sinks
  final controller = StreamController<List<Order>>();
  final Map<String, List<Order>> storeOrdersMap = {};
  final List<StreamSubscription> subs = [];

  for (final storeId in storeIds) {
    final ds = OrderRemoteDataSource(FirebaseDatabase.instance, storeId);
    final repo = OrderRepositoryImpl(ds);

    final sub = repo.watchByDateRange(range.start, range.end).listen((orders) {
      storeOrdersMap[storeId] = orders;
      final combined = storeOrdersMap.values.expand((e) => e).toList();
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!controller.isClosed) {
        controller.add(combined);
      }
    }, onError: (e) {
      debugPrint('Error watching orders for store $storeId: $e');
    });
    subs.add(sub);
  }

  controller.onCancel = () {
    for (final sub in subs) {
      sub.cancel();
    }
    controller.close();
  };

  return controller.stream.debounce(const Duration(milliseconds: 250));
}

final returnOrdersByDateRangeProvider = StreamProvider.autoDispose
    .family<List<ReturnOrder>, DateTimeRange>((ref, range) {
  return ref
      .watch(orderRepositoryProvider)
      .watchReturnsByDateRange(range.start, range.end);
});

final returnOrdersByOrderIdProvider = StreamProvider.autoDispose
    .family<List<ReturnOrder>, String>((ref, orderId) {
  return ref.watch(orderRepositoryProvider).watchReturnsByOrderId(orderId);
});

final allBranchesReturnOrdersByDateRangeProvider = StreamProvider.autoDispose
    .family<List<ReturnOrder>, DateTimeRange>((ref, range) {
  final user = ref.watch(authProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final selectedBranches = ref.watch(selectedBranchesProvider);
  final availableStores = ref.watch(availableStoresProvider).valueOrNull ?? {};

  final targetStoreIds = StoreResolverHelper.resolveTargetStoreIds(
    selectedBranches,
    currentStoreId: currentStoreId,
    user: user,
    availableStores: availableStores,
  );

  if (targetStoreIds.isEmpty) {
    return Stream.value(<ReturnOrder>[]);
  }

  return _createCombinedReturnsStream(targetStoreIds, range);
});

Stream<List<ReturnOrder>> _createCombinedReturnsStream(
    List<String> storeIds, DateTimeRange range) {
  // ignore: close_sinks
  final controller = StreamController<List<ReturnOrder>>();
  final Map<String, List<ReturnOrder>> storeReturnsMap = {};
  final List<StreamSubscription> subs = [];

  for (final storeId in storeIds) {
    final ds = OrderRemoteDataSource(FirebaseDatabase.instance, storeId);
    final repo = OrderRepositoryImpl(ds);

    final sub =
        repo.watchReturnsByDateRange(range.start, range.end).listen((returns) {
      storeReturnsMap[storeId] = returns;
      final combined = storeReturnsMap.values.expand((e) => e).toList();
      combined.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      if (!controller.isClosed) {
        controller.add(combined);
      }
    }, onError: (e) {
      debugPrint('Error watching return orders for store $storeId: $e');
    });
    subs.add(sub);
  }

  controller.onCancel = () {
    for (final sub in subs) {
      sub.cancel();
    }
    controller.close();
  };

  return controller.stream.debounce(const Duration(milliseconds: 250));
}
