import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/customer.dart';
import 'customers_providers.dart';

class CustomerListNotifier extends AutoDisposeAsyncNotifier<List<Customer>> {
  @override
  Future<List<Customer>> build() async {
    final repo = ref.watch(customerRepositoryProvider);
    return await repo.watchAll().first;
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(customerRepositoryProvider).watchAll().first);
  }
}