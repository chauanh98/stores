import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/supplier.dart';
import '../../domain/entities/supplier_debt_transaction.dart';
import 'suppliers_providers.dart';

class SupplierListNotifier extends AutoDisposeAsyncNotifier<List<Supplier>> {
  @override
  FutureOr<List<Supplier>> build() async {
    final repo = ref.watch(supplierRepositoryProvider);
    final completer = Completer<List<Supplier>>();

    final subscription = repo.watchAll().listen(
      (suppliers) {
        if (!completer.isCompleted) {
          completer.complete(suppliers);
        } else {
          state = AsyncData(suppliers);
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

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<void> upsertSupplier(Supplier supplier) async {
    final repo = ref.read(supplierRepositoryProvider);
    await repo.upsert(supplier);
  }

  Future<void> deleteSupplier(String id) async {
    final repo = ref.read(supplierRepositoryProvider);
    await repo.delete(id);
  }

  /// Trả tiền nợ NCC (Phiếu chi trả nợ)
  Future<void> recordDebtPayment({
    required String supplierId,
    required double paymentAmount,
    String? referenceCode,
    String? note,
    String createdBy = 'Admin',
  }) async {
    if (paymentAmount <= 0) return;

    final repo = ref.read(supplierRepositoryProvider);
    final supplier = await repo.fetchById(supplierId);
    if (supplier == null) return;

    final currentDebt = supplier.currentDebt;
    final remainingDebt =
        (currentDebt - paymentAmount).clamp(0.0, double.infinity);

    final tx = SupplierDebtTransaction(
      id: 'TX_PAY_${DateTime.now().millisecondsSinceEpoch}',
      supplierId: supplierId,
      date: DateTime.now(),
      type: SupplierDebtType.payment,
      amount: -paymentAmount,
      remainingDebt: remainingDebt,
      referenceCode:
          referenceCode ?? 'PC_${DateTime.now().millisecondsSinceEpoch}',
      note: note ?? 'Thanh toán nợ nhà cung cấp',
      createdBy: createdBy,
    );

    await repo.recordDebtTransaction(tx);
    await repo.upsert(
      supplier.copyWith(currentDebt: remainingDebt),
    );
  }

  /// Điều chỉnh công nợ NCC
  Future<void> recordDebtAdjustment({
    required String supplierId,
    required double newDebt,
    String? note,
    String createdBy = 'Admin',
  }) async {
    if (newDebt < 0) return;

    final repo = ref.read(supplierRepositoryProvider);
    final supplier = await repo.fetchById(supplierId);
    if (supplier == null) return;

    final currentDebt = supplier.currentDebt;
    final diff = newDebt - currentDebt;

    final tx = SupplierDebtTransaction(
      id: 'TX_ADJ_${DateTime.now().millisecondsSinceEpoch}',
      supplierId: supplierId,
      date: DateTime.now(),
      type: SupplierDebtType.adjustment,
      amount: diff,
      remainingDebt: newDebt,
      referenceCode: 'DC_${DateTime.now().millisecondsSinceEpoch}',
      note: note ?? 'Điều chỉnh công nợ nhà cung cấp',
      createdBy: createdBy,
    );

    await repo.recordDebtTransaction(tx);
    await repo.upsert(
      supplier.copyWith(currentDebt: newDebt),
    );
  }

  /// Ghi nhận nhập kho kèm nợ NCC
  Future<void> recordImportDebt({
    required String supplierId,
    required double totalAmount,
    required double paidAmount,
    String? importCode,
    String? note,
    String createdBy = 'Admin',
  }) async {
    final repo = ref.read(supplierRepositoryProvider);
    final supplier = await repo.fetchById(supplierId);
    if (supplier == null) return;

    final debtIncrease = (totalAmount - paidAmount).clamp(0.0, double.infinity);
    final newTotalPurchase = supplier.totalPurchase + totalAmount;
    final newDebt = supplier.currentDebt + debtIncrease;

    if (debtIncrease > 0) {
      final tx = SupplierDebtTransaction(
        id: 'TX_IMP_${DateTime.now().millisecondsSinceEpoch}',
        supplierId: supplierId,
        date: DateTime.now(),
        type: SupplierDebtType.importBill,
        amount: debtIncrease,
        remainingDebt: newDebt,
        referenceCode:
            importCode ?? 'PN_${DateTime.now().millisecondsSinceEpoch}',
        note: note ?? 'Nhập hàng phát sinh công nợ',
        createdBy: createdBy,
      );
      await repo.recordDebtTransaction(tx);
    }

    await repo.upsert(
      supplier.copyWith(
        totalPurchase: newTotalPurchase,
        currentDebt: newDebt,
      ),
    );
  }
}
