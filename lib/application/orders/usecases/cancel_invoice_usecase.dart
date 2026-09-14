import '../../../core/errors/exceptions.dart';
import '../../../data/datasources/firebase/customer_remote_data_source.dart';
import '../../../domain/entities/customer_debt_transaction.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../../domain/entities/user_account.dart';
import '../../../domain/repositories/customer_repository.dart';
import '../../../domain/repositories/inventory_repository.dart';
import '../../../domain/repositories/order_repository.dart';
import '../../../domain/repositories/product_repository.dart';

class CancelInvoiceUseCase {
  final OrderRepository orderRepository;
  final ProductRepository productRepository;
  final InventoryRepository inventoryRepository;
  final CustomerRepository customerRepository;
  final CustomerRemoteDataSource? customerDataSource;

  CancelInvoiceUseCase({
    required this.orderRepository,
    required this.productRepository,
    required this.inventoryRepository,
    required this.customerRepository,
    this.customerDataSource,
  });

  Future<Order> execute({
    required Order order,
    required String cancelReason,
    required UserAccount currentUser,
    required String storeId,
  }) async {
    // 1. RBAC & Business Validation
    if (!currentUser.canDeleteInvoice) {
      throw const UnauthorizedException(
          'Bạn không có quyền quản trị để hủy hóa đơn đã thanh toán.');
    }
    if (cancelReason.trim().isEmpty) {
      throw const ValidationException('Lý do hủy đơn không được để trống.');
    }
    if (order.isCancelled) {
      throw const ValidationException('Hóa đơn này đã được hủy trước đó.');
    }

    final now = DateTime.now();

    // 2. Product Inventory Stock Restoration & Audit Logging
    for (final item in order.items) {
      final qtyToRestore = item.activeQuantity;
      if (qtyToRestore <= 0) continue;

      final product = await productRepository.fetchById(item.productId);
      if (product != null) {
        if (product.isCombo && product.comboComponents.isNotEmpty) {
          for (final comp in product.comboComponents) {
            final childProduct =
                await productRepository.fetchById(comp.productId);
            if (childProduct != null) {
              final compQtyToRestore = qtyToRestore * comp.quantity;
              final updatedStocks = _updateBranchStock(
                  childProduct.branchStocks, storeId, compQtyToRestore);
              await productRepository.upsert(
                  childProduct.copyWith(branchStocks: updatedStocks));

              final tx = InventoryTransaction(
                id: 'cancel_import_${now.millisecondsSinceEpoch}_${childProduct.id}',
                productId: childProduct.id,
                type: TransactionType.import,
                quantity: compQtyToRestore,
                date: now,
                note:
                    'Hủy HĐ ${order.id} (Combo: ${product.name}): ${cancelReason.trim()}',
                createdBy: currentUser.username,
                createdByName: currentUser.displayName ?? currentUser.name,
                storeId: storeId,
              );
              await inventoryRepository.record(tx);
            }
          }
        } else {
          final updatedStocks = _updateBranchStock(
              product.branchStocks, storeId, qtyToRestore);
          await productRepository
              .upsert(product.copyWith(branchStocks: updatedStocks));

          final tx = InventoryTransaction(
            id: 'cancel_import_${now.millisecondsSinceEpoch}_${product.id}',
            productId: product.id,
            type: TransactionType.import,
            quantity: qtyToRestore,
            date: now,
            note: 'Hủy HĐ ${order.id}: ${cancelReason.trim()}',
            createdBy: currentUser.username,
            createdByName: currentUser.displayName ?? currentUser.name,
            storeId: storeId,
          );
          await inventoryRepository.record(tx);
        }
      }
    }

    // 3. Customer Debt & Sales Reversal (if registered customer)
    final customerId = order.customerId;
    if (customerId.isNotEmpty &&
        customerId != 'khach_le' &&
        customerId != 'walk_in') {
      final customer = await customerRepository.fetchById(customerId);
      if (customer != null) {
        final currentDebt = customer.displayCurrentDebt;
        final debtToReverse = order.debtAmount > 0 ? order.debtAmount : order.remainingDebt;
        final newDebt = (currentDebt - debtToReverse).clamp(0.0, double.infinity);

        final currentTotalSales = customer.totalSales ?? 0.0;
        final currentNetSales = customer.netSales ?? customer.totalSales ?? 0.0;
        final newTotalSales =
            (currentTotalSales - order.total).clamp(0.0, double.infinity);
        final newNetSales =
            (currentNetSales - order.total).clamp(0.0, double.infinity);

        final updatedCustomer = customer.copyWith(
          currentDebt: newDebt,
          totalSales: newTotalSales,
          netSales: newNetSales,
        );
        await customerRepository.upsert(updatedCustomer);

        if (debtToReverse > 0 && customerDataSource != null) {
          final debtTx = CustomerDebtTransaction(
            id: 'DEBT_CANCEL_${now.millisecondsSinceEpoch}',
            code: 'HUY_${order.id}',
            customerId: customer.id,
            date: now,
            amount: -debtToReverse,
            remainingDebt: newDebt,
            type: DebtTransactionType.adjustment,
            note: 'Hủy nợ do hủy hóa đơn ${order.id}: ${cancelReason.trim()}',
            createdBy: currentUser.username,
          );
          await customerDataSource!.saveDebtTransaction(
              customer.id, debtTx.toMap());
        }
      }
    }

    // 4. Update Order Status to 'cancelled'
    final cancelledOrder = order.copyWith(
      status: 'cancelled',
      cancelReason: cancelReason.trim(),
      cancelledAt: now,
      cancelledBy: currentUser.username,
      cancelledByName: currentUser.displayName ?? currentUser.name,
      storeId: order.storeId ?? storeId,
    );
    await orderRepository.update(cancelledOrder);

    return cancelledOrder;
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
