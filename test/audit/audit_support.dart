import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/order_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';

class AOrderRepo implements OrderRepository {
  final Map<String, Order> orders = {};
  @override
  Future<void> create(Order o) async => orders[o.id] = o;
  @override
  Future<void> update(Order o) async => orders[o.id] = o;
  @override
  Future<void> delete(String id) async => orders.remove(id);
  @override
  Future<Order?> fetchById(String id) async => orders[id];
  @override
  Stream<List<Order>> watchAll() => Stream.value(orders.values.toList());
  @override
  Stream<List<Order>> watchByCustomer(String c) => Stream.value([]);
  @override
  Stream<List<Order>> watchByDateRange(DateTime s, DateTime e) =>
      Stream.value(orders.values.toList());
  @override
  Future<void> createReturn(ReturnOrder r) async {}
}

class AProductRepo implements ProductRepository {
  final Map<String, Product> products = {};
  @override
  Future<void> delete(String id) async => products.remove(id);
  @override
  Future<List<Product>> fetchAll() async => products.values.toList();
  @override
  Future<Product?> fetchById(String id) async => products[id];
  @override
  Future<void> updateStock(String id, int n) async {}
  @override
  Future<void> upsert(Product p) async => products[p.id] = p;
  @override
  Stream<List<Product>> watchAll() => Stream.value(products.values.toList());
}

class AInvRepo implements InventoryRepository {
  final List<InventoryTransaction> txs = [];
  @override
  Future<void> record(InventoryTransaction t) async => txs.add(t);
  @override
  Stream<List<InventoryTransaction>> watchByProduct(String p) => Stream.value([]);
  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
          DateTime s, DateTime e) =>
      Stream.value(txs);
}

class ACustomerRepo implements CustomerRepository {
  final Map<String, Customer> customers = {};
  @override
  Future<void> delete(String id) async => customers.remove(id);
  @override
  Future<Customer?> fetchById(String id) async => customers[id];
  @override
  Future<void> upsert(Customer c) async => customers[c.id] = c;
  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers.values.toList());
}
