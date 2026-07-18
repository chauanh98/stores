import '../../domain/entities/order.dart';
import '../../domain/entities/order_item.dart';
import '../../domain/repositories/order_repository.dart';
import '../datasources/firebase/order_remote_data_source.dart';
import '../models/order_item_model.dart';
import '../models/order_model.dart';

class OrderRepositoryImpl implements OrderRepository {
  final OrderRemoteDataSource ds;

  OrderRepositoryImpl(this.ds);

  @override
  Future<void> create(Order order) {
    final model = OrderModel(
      id: order.id,
      customerId: order.customerId,
      createdAt: order.createdAt,
      total: order.total,
      items: order.items
          .map((i) => OrderItemModel(
                productId: i.productId,
                productName: i.productName,
                quantity: i.quantity,
                warrantyMonths: i.warrantyMonths,
                purchaseDate: i.purchaseDate,
                price: i.price,
              ))
          .toList(),
      status: order.status,
    );
    return ds.create(order.id, model.toMap());
  }

  @override
  Stream<List<Order>> watchByCustomer(String customerId) {
    return ds.watchByCustomer(customerId).map((list) {
      return list.map((m) => _mapToOrder(m)).toList();
    });
  }

  @override
  Stream<List<Order>> watchAll() {
    return ds.watchAll().map((list) {
      return list.map((m) => _mapToOrder(m)).toList();
    });
  }

  @override
  Stream<List<Order>> watchByDateRange(DateTime start, DateTime end) {
    return ds.watchByDateRange(start, end).map((list) {
      return list.map((m) => _mapToOrder(m)).toList();
    });
  }

  Order _mapToOrder(Map<String, dynamic> m) {
    final om = OrderModel.fromMap(m);
    return Order(
      id: om.id,
      customerId: om.customerId,
      createdAt: om.createdAt,
      total: om.total,
      items: om.items
          .map((im) => OrderItem(
                productId: im.productId,
                productName: im.productName,
                quantity: im.quantity,
                warrantyMonths: im.warrantyMonths,
                purchaseDate: im.purchaseDate,
                price: im.price,
              ))
          .toList(),
      status: om.status,
    );
  }
}
