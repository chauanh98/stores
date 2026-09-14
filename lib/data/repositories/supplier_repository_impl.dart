import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../domain/entities/supplier.dart';
import '../../domain/entities/supplier_debt_transaction.dart';
import '../../domain/repositories/supplier_repository.dart';
import '../datasources/firebase/supplier_remote_data_source.dart';
import '../models/supplier_debt_transaction_model.dart';
import '../models/supplier_model.dart';

Supplier _mapToSupplier(Map m) {
  return SupplierModel.fromMap(m).toDomain();
}

SupplierDebtTransaction _mapToDebtTransaction(Map m) {
  return SupplierDebtTransactionModel.fromMap(m).toDomain();
}

class SupplierRepositoryImpl implements SupplierRepository {
  SupplierRepositoryImpl(this._ds);

  final SupplierRemoteDataSource _ds;

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) {
    return _ds.watchAll(storeId: storeId).asyncMap((list) async {
      if (kIsWeb) {
        return list.map(_mapToSupplier).toList();
      }
      return await Isolate.run(() => list.map(_mapToSupplier).toList());
    });
  }

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async {
    final map = await _ds.fetchById(id, storeId: storeId);
    if (map == null) return null;
    return _mapToSupplier(map);
  }

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) {
    final model = SupplierModel.fromDomain(supplier);
    return _ds.upsert(supplier.id, model.toMap(), storeId: storeId);
  }

  @override
  Future<void> delete(String id, {String? storeId}) {
    return _ds.delete(id, storeId: storeId);
  }

  @override
  Future<void> recordDebtTransaction(
    SupplierDebtTransaction transaction, {
    String? storeId,
  }) {
    final model = SupplierDebtTransactionModel.fromDomain(transaction);
    return _ds.saveDebtTransaction(
      transaction.supplierId,
      model.toMap(),
      storeId: storeId,
    );
  }

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) {
    return _ds.watchDebtTransactions(supplierId, storeId: storeId).asyncMap((list) async {
      if (kIsWeb) {
        final txs = list.map(_mapToDebtTransaction).toList();
        txs.sort((a, b) => b.date.compareTo(a.date));
        return txs;
      }
      return await Isolate.run(() {
        final txs = list.map(_mapToDebtTransaction).toList();
        txs.sort((a, b) => b.date.compareTo(a.date));
        return txs;
      });
    });
  }

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) async {
    final list = await _ds.fetchDebtTransactions(supplierId, storeId: storeId);
    final txs = list.map(_mapToDebtTransaction).toList();
    txs.sort((a, b) => b.date.compareTo(a.date));
    return txs;
  }
}
