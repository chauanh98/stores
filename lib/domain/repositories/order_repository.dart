import '../entities/order.dart';

abstract class OrderRepository {
  Future<void> create(Order order);
  Stream<List<Order>> watchByCustomer(String customerId);
}