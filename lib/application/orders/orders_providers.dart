import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/store_resolver_helper.dart';
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

final orderRemoteDataSourceProvider = Provider<OrderRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return OrderRemoteDataSource(FirebaseDatabase.instance, storeId);
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
    StreamProvider.family<List<Order>, String>((ref, customerId) {
  return ref.watch(orderRepositoryProvider).watchByCustomer(customerId);
});

// allOrdersProvider đã bị xóa vì không được dùng ở đâu
// và tạo listener .onValue trên TOÀN BỘ node orders - rất lãng phí bandwidth

final ordersByDateRangeProvider =
    StreamProvider.family<List<Order>, DateTimeRange>((ref, range) {
  return ref
      .watch(orderRepositoryProvider)
      .watchByDateRange(range.start, range.end);
});

final allBranchesOrdersByDateRangeProvider =
    StreamProvider.family<List<Order>, DateTimeRange>((ref, range) {
  final user = ref.watch(authProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final selectedBranches = ref.watch(selectedBranchesProvider);
  final availableStores = ref.watch(availableStoresProvider).value ?? {};

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

  return controller.stream;
}

final returnOrdersByDateRangeProvider =
    StreamProvider.family<List<ReturnOrder>, DateTimeRange>((ref, range) {
  return ref
      .watch(orderRepositoryProvider)
      .watchReturnsByDateRange(range.start, range.end);
});

final returnOrdersByOrderIdProvider =
    StreamProvider.family<List<ReturnOrder>, String>((ref, orderId) {
  return ref.watch(orderRepositoryProvider).watchReturnsByOrderId(orderId);
});

final allBranchesReturnOrdersByDateRangeProvider =
    StreamProvider.family<List<ReturnOrder>, DateTimeRange>((ref, range) {
  final user = ref.watch(authProvider);
  final currentStoreId = ref.watch(currentStoreIdProvider);
  final selectedBranches = ref.watch(selectedBranchesProvider);
  final availableStores = ref.watch(availableStoresProvider).value ?? {};

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

  return controller.stream;
}

