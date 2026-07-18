import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../domain/entities/customer.dart';
import '../../domain/entities/purchase.dart';
import '../../domain/entities/warranty.dart';
import '../../domain/repositories/customer_repository.dart';
import '../datasources/firebase/customer_remote_data_source.dart';
import '../models/customer_model.dart';
import '../models/purchase_model.dart';
import '../models/warranty_model.dart';

Customer _mapToCustomer(Map m) {
  final model = CustomerModel.fromMap(m);
  return Customer(
    id: model.id,
    name: model.name,
    phone: model.phone,
    email: model.email,
    address: model.address,
    purchases: model.purchases
        .map((pm) => Purchase(
              productId: pm.productId,
              quantity: pm.quantity,
              purchaseDate: pm.purchaseDate,
              warranty: Warranty(
                months: pm.warranty.months,
                expireDate: pm.warranty.expireDate,
              ),
            ))
        .toList(),
    type: model.type,
    branch: model.branch,
    deliveryArea: model.deliveryArea,
    ward: model.ward,
    company: model.company,
    taxCode: model.taxCode,
    identityCard: model.identityCard,
    dob: model.dob,
    gender: model.gender,
    facebook: model.facebook,
    group: model.group,
    notes: model.notes,
    createdBy: model.createdBy,
    createdAt: model.createdAt,
    lastTransactionDate: model.lastTransactionDate,
    currentDebt: model.currentDebt,
    totalSales: model.totalSales,
    netSales: model.netSales,
    status: model.status,
  );
}

class CustomerRepositoryImpl implements CustomerRepository {
  CustomerRepositoryImpl(this._ds);

  final CustomerRemoteDataSource _ds;

  @override
  Stream<List<Customer>> watchAll() => _ds.watchAll().asyncMap((list) async {
        if (kIsWeb) {
          return list.map(_mapToCustomer).toList();
        }
        return await Isolate.run(() => list.map(_mapToCustomer).toList());
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
      purchases: model.purchases
          .map((pm) => Purchase(
                productId: pm.productId,
                quantity: pm.quantity,
                purchaseDate: pm.purchaseDate,
                warranty: Warranty(
                  months: pm.warranty.months,
                  expireDate: pm.warranty.expireDate,
                ),
              ))
          .toList(),
      type: model.type,
      branch: model.branch,
      deliveryArea: model.deliveryArea,
      ward: model.ward,
      company: model.company,
      taxCode: model.taxCode,
      identityCard: model.identityCard,
      dob: model.dob,
      gender: model.gender,
      facebook: model.facebook,
      group: model.group,
      notes: model.notes,
      createdBy: model.createdBy,
      createdAt: model.createdAt,
      lastTransactionDate: model.lastTransactionDate,
      currentDebt: model.currentDebt,
      totalSales: model.totalSales,
      netSales: model.netSales,
      status: model.status,
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
      purchases: customer.purchases
          .map((p) => PurchaseModel(
                productId: p.productId,
                quantity: p.quantity,
                purchaseDate: p.purchaseDate,
                warranty: WarrantyModel(
                  months: p.warranty.months,
                  expireDate: p.warranty.expireDate,
                ),
              ))
          .toList(),
      type: customer.type,
      branch: customer.branch,
      deliveryArea: customer.deliveryArea,
      ward: customer.ward,
      company: customer.company,
      taxCode: customer.taxCode,
      identityCard: customer.identityCard,
      dob: customer.dob,
      gender: customer.gender,
      facebook: customer.facebook,
      group: customer.group,
      notes: customer.notes,
      createdBy: customer.createdBy,
      createdAt: customer.createdAt,
      lastTransactionDate: customer.lastTransactionDate,
      currentDebt: customer.currentDebt,
      totalSales: customer.totalSales,
      netSales: customer.netSales,
      status: customer.status,
    ).toMap();
    return _ds.upsert(customer.id, map);
  }

  @override
  Future<void> delete(String id) => _ds.delete(id);
}
