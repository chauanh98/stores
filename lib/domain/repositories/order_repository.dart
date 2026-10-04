import '../entities/order.dart';
import '../entities/return_order.dart';

abstract class OrderRepository {
  Future<void> create(Order order);

  Future<void> update(Order order);

  Future<void> delete(String orderId);

  Future<Order?> fetchById(String orderId);

  Stream<List<Order>> watchByCustomer(String customerId);

  Stream<List<Order>> watchAll();

  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end);
}

abstract class OrderRepositoryDraftHandler {
  Stream<List<Order>> watchDraftOrders();
}

extension OrderRepositoryDraftExt on OrderRepository {
  Stream<List<Order>> watchDraftOrders() {
    final self = this;
    if (self is OrderRepositoryDraftHandler) {
      return (self as OrderRepositoryDraftHandler).watchDraftOrders();
    }
    return Stream.value([]);
  }
}

abstract class OrderRepositoryReturnHandler {
  Future<void> createReturn(ReturnOrder returnOrder);
  Future<ReturnOrder?> fetchReturnById(String returnId);
  Stream<List<ReturnOrder>> watchReturnsByDateRange(
      DateTime start, DateTime end);
  Stream<List<ReturnOrder>> watchReturnsByOrderId(String orderId);
  Stream<List<ReturnOrder>> watchAllReturns();
}

extension OrderRepositoryReturnExt on OrderRepository {
  Future<void> createReturn(ReturnOrder returnOrder) async {
    final self = this;
    if (self is OrderRepositoryReturnHandler) {
      return (self as OrderRepositoryReturnHandler).createReturn(returnOrder);
    }
  }

  Future<ReturnOrder?> fetchReturnById(String returnId) async {
    final self = this;
    if (self is OrderRepositoryReturnHandler) {
      return (self as OrderRepositoryReturnHandler).fetchReturnById(returnId);
    }
    return null;
  }

  Stream<List<ReturnOrder>> watchReturnsByDateRange(
      DateTime start, DateTime end) {
    final self = this;
    if (self is OrderRepositoryReturnHandler) {
      return (self as OrderRepositoryReturnHandler)
          .watchReturnsByDateRange(start, end);
    }
    return Stream.value([]);
  }

  Stream<List<ReturnOrder>> watchReturnsByOrderId(String orderId) {
    final self = this;
    if (self is OrderRepositoryReturnHandler) {
      return (self as OrderRepositoryReturnHandler)
          .watchReturnsByOrderId(orderId);
    }
    return Stream.value([]);
  }

  Stream<List<ReturnOrder>> watchAllReturns() {
    final self = this;
    if (self is OrderRepositoryReturnHandler) {
      return (self as OrderRepositoryReturnHandler).watchAllReturns();
    }
    return Stream.value([]);
  }
}
