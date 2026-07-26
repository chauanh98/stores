import '../entities/order.dart';

abstract class OrderRepository {
  Future<void> create(Order order);

  Future<void> delete(String orderId);

  Stream<List<Order>> watchByCustomer(String customerId);

  Stream<List<Order>> watchAll();

  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end);
}
