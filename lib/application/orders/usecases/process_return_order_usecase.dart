import 'dart:math';

import '../../../core/errors/exceptions.dart';
import '../../../data/datasources/firebase/customer_remote_data_source.dart';
import '../../../domain/entities/customer_debt_transaction.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/return_order.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/user_account.dart';
import '../../../domain/repositories/customer_repository.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../../domain/repositories/order_repository.dart';
import '../../../domain/repositories/product_repository.dart';

class ProcessReturnOrderResult {
  final ReturnOrder returnOrder;
  final Order updatedOrder;
  final double totalRefund;
  final double debtDeducted;
  final double cashRefunded;

  const ProcessReturnOrderResult({
    required this.returnOrder,
    required this.updatedOrder,
    required this.totalRefund,
    required this.debtDeducted,
    required this.cashRefunded,
  });
}

class ProcessReturnOrderUseCase {
  final OrderRepository orderRepository;
  final ProductRepository productRepository;
  final InventoryRepository inventoryRepository;
  final CustomerRepository customerRepository;
  final CustomerRemoteDataSource? customerDataSource;

  ProcessReturnOrderUseCase({
    required this.orderRepository,
    required this.productRepository,
    required this.inventoryRepository,
    required this.customerRepository,
    this.customerDataSource,
  });

  Future<ProcessReturnOrderResult> execute({
    required Order originalOrder,
    required List<ReturnOrderItem> returnItems,
    required String storeId,
    required UserAccount currentUser,
    String? reason,
    String refundPaymentMethod = 'cash',
  }) async {
    // 1. Validation
    if (originalOrder.isCancelled) {
      throw const ValidationException('Không thể trả hàng cho hóa đơn đã hủy.');
    }
    if (originalOrder.status != 'completed') {
      throw const ValidationException('Chỉ có thể trả hàng cho hóa đơn đã hoàn thành.');
    }
    if (returnItems.isEmpty) {
      throw const ValidationException('Danh sách hàng trả không được để trống.');
    }


    // Validate quantities against available in original order
    for (final returnItem in returnItems) {
      if (returnItem.quantity <= 0) {
        throw ValidationException(
            'Số lượng trả của sản phẩm "${returnItem.productName}" phải lớn hơn 0.');
      }
      final orderItem = originalOrder.items.firstWhere(
        (i) => i.productId == returnItem.productId,
        orElse: () => throw ValidationException(
            'Sản phẩm "${returnItem.productName}" không tồn tại trong hóa đơn gốc.'),
      );
      if (returnItem.quantity > orderItem.activeQuantity) {
        throw ValidationException(
            'Số lượng trả (${returnItem.quantity}) vượt quá số lượng khả dụng (${orderItem.activeQuantity}) của sản phẩm "${orderItem.productName}".');
      }
    }

    final now = DateTime.now();

    // 2. Financial calculation
    final totalRefund = returnItems.fold<double>(
        0.0, (sum, item) => sum + (item.price * item.quantity));
    final remainingDebt = originalOrder.remainingDebt;
    final debtDeducted = min(totalRefund, remainingDebt);
    final cashRefunded = (totalRefund - debtDeducted).clamp(0.0, double.infinity);

    // 3. Product Inventory Stock Restoration & Logging
    for (final returnItem in returnItems) {
      final product = await productRepository.fetchById(returnItem.productId);
      if (product != null) {
        if (product.isCombo && product.comboComponents.isNotEmpty) {
          for (final comp in product.comboComponents) {
            final childProduct =
                await productRepository.fetchById(comp.productId);
            if (childProduct != null) {
              final qtyToRestore = returnItem.quantity * comp.quantity;
              final updatedStocks = _updateBranchStock(
                  childProduct.branchStocks, storeId, qtyToRestore);
              await productRepository.upsert(
                  childProduct.copyWith(branchStocks: updatedStocks));

              final tx = InventoryTransaction(
                id: 'return_import_${now.millisecondsSinceEpoch}_${childProduct.id}',
                productId: childProduct.id,
                type: TransactionType.import,
                quantity: qtyToRestore,
                date: now,
                note:
                    'Trả hàng HĐ ${originalOrder.id} (Combo: ${product.name}): ${reason ?? 'Khách trả hàng'}',
                createdBy: currentUser.username,
                createdByName: currentUser.displayName ?? currentUser.name,
                storeId: storeId,
              );
              await inventoryRepository.record(tx);
            }
          }
        } else {
          final qtyToRestore = returnItem.quantity;
          final updatedStocks = _updateBranchStock(
              product.branchStocks, storeId, qtyToRestore);
          await productRepository
              .upsert(product.copyWith(branchStocks: updatedStocks));

          final tx = InventoryTransaction(
            id: 'return_import_${now.millisecondsSinceEpoch}_${product.id}',
            productId: product.id,
            type: TransactionType.import,
            quantity: qtyToRestore,
            date: now,
            note:
                'Trả hàng HĐ ${originalOrder.id}: ${reason ?? 'Khách trả hàng'}',
            createdBy: currentUser.username,
            createdByName: currentUser.displayName ?? currentUser.name,
            storeId: storeId,
          );
          await inventoryRepository.record(tx);
        }
      }
    }

    // 4. Customer Debt & Sales Adjustment (if registered customer)
    final customerId = originalOrder.customerId;
    if (customerId.isNotEmpty &&
        customerId != 'khach_le' &&
        customerId != 'walk_in') {
      final customer = await customerRepository.fetchById(customerId);
      if (customer != null) {
        final currentDebt = customer.displayCurrentDebt;
        final newDebt = (currentDebt - debtDeducted).clamp(0.0, double.infinity);
        final currentNetSales = customer.netSales ?? customer.totalSales ?? 0.0;
        final newNetSales =
            (currentNetSales - totalRefund).clamp(0.0, double.infinity);

        final updatedCustomer = customer.copyWith(
          currentDebt: newDebt,
          netSales: newNetSales,
        );
        await customerRepository.upsert(updatedCustomer);

        if (debtDeducted > 0 && customerDataSource != null) {
          final debtTx = CustomerDebtTransaction(
            id: 'DEBT_RETURN_${now.millisecondsSinceEpoch}',
            code: 'TH_${originalOrder.id}',
            customerId: customer.id,
            date: now,
            amount: -debtDeducted,
            remainingDebt: newDebt,
            type: DebtTransactionType.adjustment,
            note: 'Trừ nợ do trả hàng HĐ ${originalOrder.id}: ${reason ?? ''}',
            createdBy: currentUser.username,
          );
          await customerDataSource!.saveDebtTransaction(
              customer.id, debtTx.toMap());
        }
      }
    }

    // 5. Update Original Order Items and Financials
    final returnQtyMap = {
      for (final r in returnItems) r.productId: r.quantity,
    };
    final updatedItems = originalOrder.items.map((item) {
      final additionalReturned = returnQtyMap[item.productId] ?? 0;
      if (additionalReturned > 0) {
        return item.copyWith(
          returnedQuantity: item.returnedQuantity + additionalReturned,
        );
      }
      return item;
    }).toList();

    final allItemsFullyReturned =
        updatedItems.every((i) => i.activeQuantity <= 0);

    final newTotal =
        (originalOrder.total - totalRefund).clamp(0.0, double.infinity);
    final newDebtAmount =
        (originalOrder.debtAmount - debtDeducted).clamp(0.0, double.infinity);
    final newAmountPaid =
        (originalOrder.amountPaid - cashRefunded).clamp(0.0, double.infinity);

    final updatedOrder = originalOrder.copyWith(
      items: updatedItems,
      total: newTotal,
      debtAmount: newDebtAmount,
      amountPaid: newAmountPaid,
      status: allItemsFullyReturned ? 'returned' : originalOrder.status,
    );

    await orderRepository.update(updatedOrder);

    // 6. Create ReturnOrder Entity
    final returnOrderId = 'TH_${now.millisecondsSinceEpoch}';
    final returnOrder = ReturnOrder(
      id: returnOrderId,
      orderId: originalOrder.id,
      customerId: originalOrder.customerId,
      storeId: storeId,
      createdAt: now,
      items: returnItems,
      totalReturnAmount: totalRefund,
      debtDeducted: debtDeducted,
      cashRefunded: cashRefunded,
      reason: reason,
      createdBy: currentUser.username,
      createdByName: currentUser.displayName ?? currentUser.name,
      refundPaymentMethod: refundPaymentMethod,
    );

    await orderRepository.createReturn(returnOrder);

    return ProcessReturnOrderResult(
      returnOrder: returnOrder,
      updatedOrder: updatedOrder,
      totalRefund: totalRefund,
      debtDeducted: debtDeducted,
      cashRefunded: cashRefunded,
    );
  }

  Map<String, int> _updateBranchStock(
      Map<String, int> currentStocks, String storeId, int delta) {
    final stocks = Map<String, int>.from(currentStocks);
    String targetKey = storeId;
    if (!stocks.containsKey(storeId)) {
      if (storeId == 'store_001' && stocks.containsKey('branch_1')) {
        targetKey = 'branch_1';
      } else if (storeId == 'store_002' && stocks.containsKey('branch_2')) {
        targetKey = 'branch_2';
      } else if (storeId == 'branch_1' && stocks.containsKey('store_001')) {
        targetKey = 'store_001';
      } else if (storeId == 'branch_2' && stocks.containsKey('store_002')) {
        targetKey = 'store_002';
      }
    }
    final current = stocks[targetKey] ?? 0;
    stocks[targetKey] = current + delta;
    return stocks;
  }
}
