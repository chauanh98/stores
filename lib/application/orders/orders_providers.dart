import 'dart:async';

import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/order_remote_data_source.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../domain/entities/order.dart';
import '../../domain/repositories/order_repository.dart';
import '../auth/auth_providers.dart';
import '../reports/overview_providers.dart';

final orderRemoteDataSourceProvider = Provider<OrderRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return OrderRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final ds = ref.watch(orderRemoteDataSourceProvider);
  return OrderRepositoryImpl(ds);
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

  // Ánh xạ chi nhánh được chọn sang store ID tương ứng
  final List<String> targetStoreIds = [];
  if (user?.isAdmin == true) {
    for (final branchId in selectedBranches) {
      if (currentStoreId == 'store_001') {
        if (branchId == 'branch_1') {
          targetStoreIds.add('store_001');
        } else if (branchId == 'branch_2') {
          targetStoreIds.add('store_002');
        }
      } else if (currentStoreId == 'store_002') {
        if (branchId == 'branch_1') {
          targetStoreIds.add('store_002');
        } else if (branchId == 'branch_2') {
          targetStoreIds.add('store_001');
        }
      }
    }
  } else {
    targetStoreIds.add(currentStoreId);
  }

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
      print('Error watching orders for store $storeId: $e');
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
