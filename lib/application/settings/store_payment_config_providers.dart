import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/datasources/firebase/store_payment_config_remote_data_source.dart';
import '../../domain/entities/store_payment_config.dart';
import '../auth/auth_providers.dart';

final storePaymentConfigDataSourceProvider =
    Provider<StorePaymentConfigRemoteDataSource>((ref) {
  try {
    return StorePaymentConfigRemoteDataSource(FirebaseDatabase.instance);
  } catch (_) {
    return StorePaymentConfigRemoteDataSource();
  }
});

final storePaymentConfigStreamProvider =
    StreamProvider<StorePaymentConfig>((ref) {
  try {
    final storeId = ref.watch(currentStoreIdProvider);
    final ds = ref.watch(storePaymentConfigDataSourceProvider);
    return ds.watchConfig(storeId);
  } catch (_) {
    return const Stream.empty();
  }
});

final storePaymentConfigProvider = Provider<StorePaymentConfig>((ref) {
  try {
    final asyncVal = ref.watch(storePaymentConfigStreamProvider);
    final storeId = ref.watch(currentStoreIdProvider);
    return asyncVal.value ?? StorePaymentConfig(storeId: storeId);
  } catch (_) {
    final storeId = ref.watch(currentStoreIdProvider);
    return StorePaymentConfig(storeId: storeId);
  }
});
