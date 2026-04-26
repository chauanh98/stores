import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/customer_remote_data_source.dart';
import '../../data/repositories/customer_repository_impl.dart';
import '../../domain/entities/customer.dart';
import '../../domain/repositories/customer_repository.dart';
import 'customer_list_notifier.dart';

import '../auth/auth_providers.dart';

final customerRemoteDataSourceProvider = Provider<CustomerRemoteDataSource>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  return CustomerRemoteDataSource(FirebaseDatabase.instance, storeId);
});

final customerRepositoryProvider = Provider<CustomerRepository>((ref) {
  final ds = ref.watch(customerRemoteDataSourceProvider);
  return CustomerRepositoryImpl(ds);
});

final customerListNotifierProvider =
AutoDisposeAsyncNotifierProvider<CustomerListNotifier, List<Customer>>(
  CustomerListNotifier.new,
);