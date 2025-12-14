import '../../domain/entities/customer.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/warranty.dart';
import '../../domain/repositories/customer_repository.dart';
import '../datasources/firebase/customer_remote_data_source.dart';
import '../models/customer_model.dart';
import '../models/purchase_model.dart';
import '../models/warranty_model.dart';

class CustomerRepositoryImpl implements CustomerRepository {
  CustomerRepositoryImpl(this._ds);

  final CustomerRemoteDataSource _ds;

  @override
  Stream<List<Customer>> watchAll() => _ds.watchAll().map((list) {
    return list.map((m) {
      final model = CustomerModel.fromMap(m);
      return Customer(
        id: model.id,
        name: model.name,
        phone: model.phone,
        email: model.email,
        address: model.address,
        purchases: model.purchases.map((pm) => Purchase(
          productId: pm.productId,
          quantity: pm.quantity,
          purchaseDate: pm.purchaseDate,
          warranty: Warranty(
            months: pm.warranty.months,
            expireDate: pm.warranty.expireDate,
          ),
        )).toList(),
      );
    }).toList();
  });

  @override
  Future<Customer?> fetchById(String id) async {
    final m = await _ds.fetchById(id);
    if (m == null) return null;
    final model = CustomerModel.fromMap(m);
    return Customer(
      id: model.id,
      name: model.name,
      phone: model.phone,
      email: model.email,
      address: model.address,
      purchases: model.purchases.map((pm) => Purchase(
        productId: pm.productId,
        quantity: pm.quantity,
        purchaseDate: pm.purchaseDate,
        warranty: Warranty(
          months: pm.warranty.months,
          expireDate: pm.warranty.expireDate,
        ),
      )).toList(),
    );
  }

  @override
  Future<void> upsert(Customer customer) {
    final map = CustomerModel(
      id: customer.id,
      name: customer.name,
      phone: customer.phone,
      email: customer.email,
      address: customer.address,
      purchases: customer.purchases.map((p) => PurchaseModel(
        productId: p.productId,
        quantity: p.quantity,
        purchaseDate: p.purchaseDate,
        warranty: WarrantyModel(
          months: p.warranty.months,
          expireDate: p.warranty.expireDate,
        ),
      )).toList(),
    ).toMap();
    return _ds.upsert(customer.id, map);
  }

  @override
  Future<void> delete(String id) => _ds.delete(id);
}