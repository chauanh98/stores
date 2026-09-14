import '../../../core/errors/exceptions.dart';
import '../../../data/datasources/firebase/customer_remote_data_source.dart';
import '../../../domain/entities/customer_debt_transaction.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/user_account.dart';
import '../../../domain/repositories/customer_repository.dart';
import '../../../domain/repositories/order_repository.dart';

class CollectInvoiceDebtUseCase {
  final OrderRepository orderRepository;
  final CustomerRepository customerRepository;
  final CustomerRemoteDataSource? customerDataSource;

  CollectInvoiceDebtUseCase({
    required this.orderRepository,
    required this.customerRepository,
    this.customerDataSource,
  });

  Future<Order> execute({
    required Order order,
    required double amount,
    required String paymentMethod, // 'cash' or 'transfer'
    required UserAccount currentUser,
    String? note,
  }) async {
    // 1. Validation
    if (order.isCancelled) {
      throw const ValidationException('Không thể thu nợ cho hóa đơn đã hủy.');
    }
    if (order.status != 'completed') {
      throw const ValidationException('Chỉ có thể thu nợ cho hóa đơn đã hoàn thành.');
    }
    if (amount <= 0) {
      throw const ValidationException('Số tiền thu nợ phải lớn hơn 0.');
    }

    if (amount > order.remainingDebt + 0.01) {
      throw ValidationException(
          'Số tiền thu ($amount) vượt quá công nợ còn lại (${order.remainingDebt}) của hóa đơn.');
    }

    final now = DateTime.now();

    // 2. Financial calculation
    final newAmountPaid = order.amountPaid + amount;
    final newDebtAmount = (order.debtAmount - amount).clamp(0.0, double.infinity);

    // 3. Update Order
    final updatedOrder = order.copyWith(
      amountPaid: newAmountPaid,
      debtAmount: newDebtAmount,
    );
    await orderRepository.update(updatedOrder);

    // 4. Update Customer Debt & Record Debt Transaction
    final customerId = order.customerId;
    if (customerId.isNotEmpty &&
        customerId != 'khach_le' &&
        customerId != 'walk_in') {
      final customer = await customerRepository.fetchById(customerId);
      if (customer != null) {
        final currentDebt = customer.displayCurrentDebt;
        final newCustomerDebt = (currentDebt - amount).clamp(0.0, double.infinity);
        final updatedCustomer = customer.copyWith(currentDebt: newCustomerDebt);
        await customerRepository.upsert(updatedCustomer);

        if (customerDataSource != null) {
          final txId = 'TTHD_${now.millisecondsSinceEpoch}';
          final debtTx = CustomerDebtTransaction(
            id: txId,
            code: 'TTHD${order.id}',
            customerId: customer.id,
            date: now,
            amount: -amount,
            remainingDebt: newCustomerDebt,
            type: DebtTransactionType.payment,
            note:
                'Thu nợ hóa đơn ${order.id}${note != null && note.trim().isNotEmpty ? ': $note' : ''} (${paymentMethod == 'transfer' ? 'Chuyển khoản' : 'Tiền mặt'})',
            createdBy: currentUser.username,
          );
          await customerDataSource!.saveDebtTransaction(
              customer.id, debtTx.toMap());
        }
      }
    }

    return updatedOrder;
  }
}
