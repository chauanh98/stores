import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/firebase/product_remote_data_source.dart';
import '../models/product_model.dart';

Product _mapToProduct(Map m, [String? storeId]) {
  final model = ProductModel.fromMap(m, storeId);
  return model.toEntity();
}

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._ds);

  final ProductRemoteDataSource _ds;

  @override
  Stream<List<Product>> watchAll() => _ds.watchAll().asyncMap((list) async {
        final storeId = _ds.storeId;
        if (kIsWeb) {
          return list.map((m) => _mapToProduct(m, storeId)).toList();
        }
        return await Isolate.run(
            () => list.map((m) => _mapToProduct(m, storeId)).toList());
      });

  @override
  Future<List<Product>> fetchAll() async {
    final list = await _ds.fetchAll();
    return list.map((m) => _mapToProduct(m, _ds.storeId)).toList();
  }

  @override
  Future<Product?> fetchById(String id) async {
    final m = await _ds.fetchById(id);
    if (m == null) return null;
    return _mapToProduct(m, _ds.storeId);
  }

  @override
  Future<void> upsert(Product product) {
    final map = ProductModel(
      id: product.id,
      name: product.name,
      code: product.code,
      barcode: product.barcode,
      brand: product.brand,
      model: product.model,
      price: product.price,
      costPrice: product.costPrice,
      branchStocks: product.branchStocks,
      category: product.category,
      type: product.type,
      category3Levels: product.category3Levels,
      unit: product.unit,
      description: product.description,
      noteTemplate: product.noteTemplate,
      components: product.components,
      imageUrl: product.imageUrl,
      images: product.images,
      isCombo: product.isCombo,
      comboComponents: product.comboComponents,
      minStock: product.minStock,
      maxStock: product.maxStock,
      units: product.units,
      allowSale: product.allowSale,
    ).toMap();
    return _ds.upsert(product.id, map);
  }

  @override
  Future<void> delete(String id) => _ds.delete(id);

  @override
  Future<void> updateStock(String id, int newStock) =>
      _ds.updateStock(id, newStock);
}
