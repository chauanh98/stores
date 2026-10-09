import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/customer.dart';
import 'customers_providers.dart';

class CustomerListNotifier extends AutoDisposeAsyncNotifier<List<Customer>> {
  @override
  FutureOr<List<Customer>> build() async {
    final repo = ref.watch(customerRepositoryProvider);
    final completer = Completer<List<Customer>>();

    final subscription = repo.watchAll().listen(
      (customers) {
        if (customers.isEmpty) {
          seedCustomers(ref);
        }
        if (!completer.isCompleted) {
          completer.complete(customers);
        } else {
          state = AsyncData(customers);
        }
      },
      onError: (err, stack) {
        if (!completer.isCompleted) {
          completer.completeError(err, stack);
        } else {
          state = AsyncError(err, stack);
        }
      },
    );

    ref.onDispose(() {
      subscription.cancel();
    });

    return completer.future;
  }

  /// Danh sách khách hàng được đồng bộ realtime, nên "làm mới" chỉ mở lại
  /// listener khi đang lỗi. Mở lại khi đang ổn sẽ tải lại toàn bộ khách hàng.
  Future<void> refresh() async {
    if (state.hasError) {
      ref.invalidateSelf();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
}
