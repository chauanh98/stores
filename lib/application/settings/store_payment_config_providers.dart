import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/firebase/store_payment_config_remote_data_source.dart';
import '../../domain/entities/store_payment_config.dart';
import '../auth/auth_providers.dart';

final storePaymentConfigDataSourceProvider =
    Provider<StorePaymentConfigRemoteDataSource>((ref) {
  return StorePaymentConfigRemoteDataSource(FirebaseDatabase.instance);
});

final storePaymentConfigStreamProvider =
    StreamProvider<StorePaymentConfig>((ref) {
  final storeId = ref.watch(currentStoreIdProvider);
  final ds = ref.watch(storePaymentConfigDataSourceProvider);
  return ds.watchConfig(storeId);
});

final storePaymentConfigProvider = Provider<StorePaymentConfig>((ref) {
  final asyncVal = ref.watch(storePaymentConfigStreamProvider);
  final storeId = ref.watch(currentStoreIdProvider);
  return asyncVal.value ?? StorePaymentConfig(storeId: storeId);
});
