import '../../domain/entities/order.dart';
import '../../domain/entities/order_item.dart';
import '../../domain/entities/return_order.dart';
import '../../domain/repositories/order_repository.dart';
import '../datasources/firebase/order_remote_data_source.dart';
import '../models/order_item_model.dart';
import '../models/order_model.dart';

class OrderRepositoryImpl
    implements OrderRepository, OrderRepositoryReturnHandler {
  final OrderRemoteDataSource ds;

  OrderRepositoryImpl(this.ds);

  @override
  Future<void> create(Order order) {
    final model = _mapToModel(order);
    return ds.create(order.id, model.toMap());
  }

  @override
  Future<void> update(Order order) {
    final model = _mapToModel(order);
    return ds.update(order.id, model.toMap());
  }

  @override
  Future<void> delete(String orderId) {
    return ds.delete(orderId);
  }

  @override
  Future<Order?> fetchById(String orderId) async {
    final m = await ds.fetchById(orderId);
    if (m == null) return null;
    return _mapToOrder(m);
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

  @override
  Future<void> createReturn(ReturnOrder returnOrder) {
    return ds.createReturn(returnOrder.id, returnOrder.toMap());
  }

  @override
  Future<ReturnOrder?> fetchReturnById(String returnId) async {
    final m = await ds.fetchReturnById(returnId);
    if (m == null) return null;
    return ReturnOrder.fromMap(m);
  }

  @override
  Stream<List<ReturnOrder>> watchReturnsByDateRange(
      DateTime start, DateTime end) {
    return ds.watchReturnsByDateRange(start, end).map((list) {
      return list.map((m) => ReturnOrder.fromMap(m)).toList();
    });
  }

  @override
  Stream<List<ReturnOrder>> watchReturnsByOrderId(String orderId) {
    return ds.watchReturnsByOrderId(orderId).map((list) {
      return list.map((m) => ReturnOrder.fromMap(m)).toList();
    });
  }

  OrderModel _mapToModel(Order order) {
    return OrderModel(
      id: order.id,
      customerId: order.customerId,
      customerName: order.customerName,
      createdAt: order.createdAt,
      total: order.total,
      discount: order.discount,
      items: order.items
          .map((i) => OrderItemModel(
                productId: i.productId,
                productName: i.productName,
                quantity: i.quantity,
                warrantyMonths: i.warrantyMonths,
                purchaseDate: i.purchaseDate,
                price: i.price,
                returnedQuantity: i.returnedQuantity,
              ))
          .toList(),
      status: order.status,
      amountPaid: order.amountPaid,
      debtAmount: order.isCancelled ? 0.0 : order.debtAmount,
      paymentMethod: order.paymentMethod,
      createdBy: order.createdBy,
      createdByName: order.createdByName,
      cancelReason: order.cancelReason,
      cancelledAt: order.cancelledAt,
      cancelledBy: order.cancelledBy,
      cancelledByName: order.cancelledByName,
      storeId: order.storeId,
      cashAmount: order.cashAmount,
      transferAmount: order.transferAmount,
      note: order.note,
    );
  }

  Order _mapToOrder(Map<String, dynamic> m) {
    final om = OrderModel.fromMap(m);
    return Order(
      id: om.id,
      customerId: om.customerId,
      customerName: om.customerName,
      createdAt: om.createdAt,
      total: om.total,
      discount: om.discount,
      items: om.items
          .map((im) => OrderItem(
                productId: im.productId,
                productName: im.productName,
                quantity: im.quantity,
                warrantyMonths: im.warrantyMonths,
                purchaseDate: im.purchaseDate,
                price: im.price,
                returnedQuantity: im.returnedQuantity,
              ))
          .toList(),
      status: om.status,
      amountPaid: om.amountPaid,
      debtAmount: om.debtAmount,
      paymentMethod: om.paymentMethod,
      createdBy: om.createdBy,
      createdByName: om.createdByName,
      cancelReason: om.cancelReason,
      cancelledAt: om.cancelledAt,
      cancelledBy: om.cancelledBy,
      cancelledByName: om.cancelledByName,
      storeId: om.storeId,
      cashAmount: om.cashAmount,
      transferAmount: om.transferAmount,
      note: om.note,
    );
  }
}
