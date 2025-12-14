import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/product_remote_data_source.dart';
import '../../data/repositories/product_repository_impl.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';

final productRemoteDataSourceProvider = Provider<ProductRemoteDataSource>((ref) {
  return ProductRemoteDataSource(FirebaseDatabase.instance);
});

final productRepositoryProvider = Provider<ProductRepository>((ref) {
  final ds = ref.watch(productRemoteDataSourceProvider);
  return ProductRepositoryImpl(ds);
});

final productListProvider = StreamProvider.autoDispose<List<Product>>((ref) {
  return ref.watch(productRepositoryProvider).watchAll();
});