import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_database/firebase_database.dart';

import '../../data/datasources/firebase/order_remote_data_source.dart';
import '../../data/repositories/order_repository_impl.dart';
import '../../domain/repositories/order_repository.dart';
import '../../domain/entities/order.dart';

final orderRemoteDataSourceProvider = Provider<OrderRemoteDataSource>((ref) {
  return OrderRemoteDataSource(FirebaseDatabase.instance);
});

final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  final ds = ref.watch(orderRemoteDataSourceProvider);
  return OrderRepositoryImpl(ds);
});

final customerOrdersProvider =
StreamProvider.family<List<Order>, String>((ref, customerId) {
  return ref.watch(orderRepositoryProvider).watchByCustomer(customerId);
});