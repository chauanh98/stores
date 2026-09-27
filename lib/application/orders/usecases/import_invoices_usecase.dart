import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/firebase/customer_remote_data_source.dart';
import '../../../domain/entities/customer_debt_transaction.dart';
import '../../../domain/entities/import_result.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/purchase.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/warranty.dart';
import '../../../domain/repositories/customer_repository.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../../domain/repositories/order_repository.dart';
import '../../../domain/repositories/product_repository.dart';
import '../../customers/customers_providers.dart';
import '../../inventory/inventory_providers.dart';
import '../../products/products_providers.dart';
import '../orders_providers.dart';

final importInvoicesUseCaseProvider = Provider<ImportInvoicesUseCase>((ref) {
  return ImportInvoicesUseCase(
    orderRepository: ref.watch(orderRepositoryProvider),
    productRepository: ref.watch(productRepositoryProvider),
    inventoryRepository: ref.watch(inventoryRepositoryProvider),
    customerRepository: ref.watch(customerRepositoryProvider),
    customerDataSource: ref.watch(customerRemoteDataSourceProvider),
  );
});

class ImportInvoicesUseCase {
  final OrderRepository orderRepository;
  final ProductRepository productRepository;
  final InventoryRepository inventoryRepository;
  final CustomerRepository customerRepository;
  final CustomerRemoteDataSource? customerDataSource;

  ImportInvoicesUseCase({
    required this.orderRepository,
    required this.productRepository,
    required this.inventoryRepository,
    required this.customerRepository,
    this.customerDataSource,
  });

  Future<ImportResult> execute({
    required List<Order> orders,
    required String targetStoreId,
  }) async {
    if (orders.isEmpty) {
      return const ImportResult();
    }

    int added = 0;
    int updated = 0;
    int skipped = 0;
    int errors = 0;
    final List<String> errorMessages = [];

    final now = DateTime.now();

    for (final order in orders) {
      try {
        final orderId = order.id.trim();
        if (orderId.isEmpty) {
          errors++;
          errorMessages.add('Hóa đơn không có mã hợp lệ.');
          continue;
        }

        var orderTotal = order.total;
        var orderDiscount = order.discount;
        if (order.items.isNotEmpty) {
          final itemsSum = order.items.fold<double>(
              0.0, (sum, item) => sum + (item.price * item.quantity));
          if (itemsSum > orderTotal + 0.01) {
            orderTotal = itemsSum;
            if (orderDiscount <= 0.01) {
              orderDiscount = itemsSum - order.total;
            }
          }
        }

        // 1. Check if invoice already exists (Upsert logic: update without double-deducting inventory)
        final existingOrder = await orderRepository.fetchById(orderId);
        if (existingOrder != null) {
          final resolvedItems = (order.items.isNotEmpty &&
                  !(order.items.length == 1 &&
                      order.items.first.productId.startsWith('inv_item_') &&
                      existingOrder.items.isNotEmpty &&
                      !existingOrder.items.first.productId
                          .startsWith('inv_item_')))
              ? order.items
              : (existingOrder.items.isNotEmpty
                  ? existingOrder.items
                  : order.items);

          final updatedOrder = existingOrder.copyWith(
            customerId: order.customerId.trim().isNotEmpty
                ? order.customerId
                : existingOrder.customerId,
            total: orderTotal,
            discount: orderDiscount,
            status: order.status,
            customerName: (order.customerName != null &&
                    order.customerName!.trim().isNotEmpty)
                ? order.customerName
                : existingOrder.customerName,
            amountPaid: order.amountPaid,
            debtAmount: order.isCancelled ? 0.0 : order.debtAmount,
            paymentMethod: order.paymentMethod,
            items: resolvedItems,
            storeId: (order.storeId != null && order.storeId!.isNotEmpty)
                ? order.storeId
                : existingOrder.storeId,
            cashAmount: order.cashAmount ?? existingOrder.cashAmount,
            transferAmount:
                order.transferAmount ?? existingOrder.transferAmount,
            note: order.note ?? existingOrder.note,
            createdBy:
                (order.createdBy != null && order.createdBy!.trim().isNotEmpty)
                    ? order.createdBy
                    : existingOrder.createdBy,
            createdByName: (order.createdByName != null &&
                    order.createdByName!.trim().isNotEmpty)
                ? order.createdByName
                : existingOrder.createdByName,
            cancelReason: (order.cancelReason != null &&
                    order.cancelReason!.trim().isNotEmpty)
                ? order.cancelReason
                : existingOrder.cancelReason,
            cancelledAt: order.cancelledAt ??
                (order.status == 'cancelled' &&
                        existingOrder.cancelledAt == null
                    ? now
                    : existingOrder.cancelledAt),
            cancelledBy: order.cancelledBy ?? existingOrder.cancelledBy,
            cancelledByName:
                order.cancelledByName ?? existingOrder.cancelledByName,
          );
          await orderRepository.update(updatedOrder);
          updated++;
          continue;
        }

        // 2. Insert new invoice
        final orderToInsert =
            (order.storeId != null && order.storeId!.isNotEmpty)
                ? order.copyWith(
                    total: orderTotal,
                    discount: orderDiscount,
                    debtAmount: order.isCancelled ? 0.0 : order.debtAmount,
                  )
                : order.copyWith(
                    storeId: targetStoreId,
                    total: orderTotal,
                    discount: orderDiscount,
                    debtAmount: order.isCancelled ? 0.0 : order.debtAmount,
                  );
        await orderRepository.create(orderToInsert);

        // 3. Link customer (update customer purchases & debt if order has debt)
        if (order.customerId.trim().isNotEmpty && !order.isCancelled) {
          try {
            final customer =
                await customerRepository.fetchById(order.customerId.trim());
            if (customer != null) {
              // Add purchased items
              final newPurchases = List<Purchase>.from(customer.purchases);
              for (final item in order.items) {
                newPurchases.add(Purchase(
                  productId: item.productId,
                  quantity: item.quantity,
                  purchaseDate: item.purchaseDate,
                  warranty: Warranty(
                    months: item.warrantyMonths,
                    expireDate: DateTime(
                      item.purchaseDate.year,
                      item.purchaseDate.month + item.warrantyMonths,
                      item.purchaseDate.day,
                    ),
                  ),
                ));
              }

              final newTotalSales = (customer.totalSales ?? 0.0) + order.total;
              final newNetSales = (customer.netSales ?? 0.0) + order.netPayable;
              double updatedDebt = customer.currentDebt ?? 0.0;
              if (order.remainingDebt > 0) {
                updatedDebt += order.remainingDebt;
              }

              final updatedCustomer = customer.copyWith(
                purchases: newPurchases,
                totalSales: newTotalSales,
                netSales: newNetSales,
                currentDebt: updatedDebt,
                lastTransactionDate: order.createdAt.toIso8601String(),
              );
              await customerRepository.upsert(updatedCustomer);

              // Record debt transaction if debt > 0
              if (order.remainingDebt > 0 && customerDataSource != null) {
                final debtTx = CustomerDebtTransaction(
                  id: 'DEBT_${order.id}_${now.millisecondsSinceEpoch}',
                  code: order.id,
                  customerId: customer.id,
                  date: order.createdAt,
                  amount: order.remainingDebt,
                  remainingDebt: updatedDebt,
                  type: DebtTransactionType.invoice,
                  note: 'Nợ hóa đơn ${order.id}',
                );
                await customerDataSource!
                    .saveDebtTransaction(customer.id, debtTx.toMap());
              }
            }
          } catch (e) {
            // Customer linking failure should not crash inventory deduction
          }
        }

        // 4. Deduct inventory stock for items from targetStoreId
        if (!order.isCancelled) {
          for (final item in order.items) {
            try {
              final product = await productRepository.fetchById(item.productId);
              if (product != null) {
                if (product.isCombo && product.comboComponents.isNotEmpty) {
                  for (final comp in product.comboComponents) {
                    final child =
                        await productRepository.fetchById(comp.productId);
                    if (child != null) {
                      final childStocks =
                          Map<String, int>.from(child.branchStocks);
                      String childKey = targetStoreId;
                      if (!childStocks.containsKey(targetStoreId)) {
                        if (targetStoreId == 'store_001' &&
                            childStocks.containsKey('branch_1')) {
                          childKey = 'branch_1';
                        } else if (targetStoreId == 'store_002' &&
                            childStocks.containsKey('branch_2')) {
                          childKey = 'branch_2';
                        } else if (targetStoreId == 'branch_1' &&
                            childStocks.containsKey('store_001')) {
                          childKey = 'store_001';
                        } else if (targetStoreId == 'branch_2' &&
                            childStocks.containsKey('store_002')) {
                          childKey = 'store_002';
                        }
                      }

                      final currentChildStock = childStocks[childKey] ?? 0;
                      final qtyToDeduct = item.quantity * comp.quantity;
                      childStocks[childKey] =
                          (currentChildStock - qtyToDeduct).clamp(0, 999999);

                      await productRepository
                          .upsert(child.copyWith(branchStocks: childStocks));

                      await inventoryRepository.record(InventoryTransaction(
                        id: 'export_${order.id}_${child.id}_${now.millisecondsSinceEpoch}',
                        productId: child.id,
                        type: TransactionType.export,
                        quantity: qtyToDeduct,
                        date: order.createdAt,
                        note: '${order.id} (Combo: ${product.name})',
                        storeId: targetStoreId,
                      ));
                    }
                  }
                } else {
                  final branchStocks =
                      Map<String, int>.from(product.branchStocks);
                  String storeKey = targetStoreId;
                  if (!branchStocks.containsKey(targetStoreId)) {
                    if (targetStoreId == 'store_001' &&
                        branchStocks.containsKey('branch_1')) {
                      storeKey = 'branch_1';
                    } else if (targetStoreId == 'store_002' &&
                        branchStocks.containsKey('branch_2')) {
                      storeKey = 'branch_2';
                    } else if (targetStoreId == 'branch_1' &&
                        branchStocks.containsKey('store_001')) {
                      storeKey = 'store_001';
                    } else if (targetStoreId == 'branch_2' &&
                        branchStocks.containsKey('store_002')) {
                      storeKey = 'store_002';
                    }
                  }

                  final currentStock = branchStocks[storeKey] ?? 0;
                  branchStocks[storeKey] =
                      (currentStock - item.quantity).clamp(0, 999999);

                  await productRepository
                      .upsert(product.copyWith(branchStocks: branchStocks));

                  await inventoryRepository.record(InventoryTransaction(
                    id: 'export_${order.id}_${product.id}_${now.millisecondsSinceEpoch}',
                    productId: product.id,
                    type: TransactionType.export,
                    quantity: item.quantity,
                    date: order.createdAt,
                    note: order.id,
                    storeId: targetStoreId,
                  ));
                }
              }
            } catch (e) {
              // Inventory deduction failure for single item
            }
          }
        }

        added++;
      } catch (e) {
        errors++;
        errorMessages.add('Lỗi tại hóa đơn ${order.id}: $e');
      }
    }

    return ImportResult(
      total: orders.length,
      added: added,
      updated: updated,
      skipped: skipped,
      errors: errors,
      errorMessages: errorMessages,
    );
  }
}
