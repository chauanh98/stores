import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/firebase/product_remote_data_source.dart';
import '../models/product_model.dart';

Product _mapToProduct(Map m) {
  final model = ProductModel.fromMap(m);
  return Product(
    id: model.id,
    name: model.name,
    code: model.code,
    barcode: model.barcode,
    brand: model.brand,
    model: model.model,
    price: model.price,
    costPrice: model.costPrice,
    branchStocks: model.branchStocks,
    category: model.category,
    type: model.type,
    category3Levels: model.category3Levels,
    unit: model.unit,
    description: model.description,
    noteTemplate: model.noteTemplate,
    components: model.components,
    imageUrl: model.imageUrl,
    isCombo: model.isCombo,
    comboComponents: model.comboComponents,
  );
}

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._ds);

  final ProductRemoteDataSource _ds;

  @override
  Stream<List<Product>> watchAll() => _ds.watchAll().asyncMap((list) async {
        if (kIsWeb) {
          return list.map(_mapToProduct).toList();
        }
        return await Isolate.run(() => list.map(_mapToProduct).toList());
      });

  @override
  Future<List<Product>> fetchAll() async {
    final list = await _ds.fetchAll();
    return list.map(_mapToProduct).toList();
  }

  @override
  Future<Product?> fetchById(String id) async {
    final m = await _ds.fetchById(id);
    if (m == null) return null;
    final model = ProductModel.fromMap(m);
    return Product(
      id: model.id,
      name: model.name,
      code: model.code,
      barcode: model.barcode,
      brand: model.brand,
      model: model.model,
      price: model.price,
      costPrice: model.costPrice,
      branchStocks: model.branchStocks,
      category: model.category,
      type: model.type,
      category3Levels: model.category3Levels,
      unit: model.unit,
      description: model.description,
      noteTemplate: model.noteTemplate,
      components: model.components,
      imageUrl: model.imageUrl,
      isCombo: model.isCombo,
      comboComponents: model.comboComponents,
    );
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
      isCombo: product.isCombo,
      comboComponents: product.comboComponents,
    ).toMap();
    return _ds.upsert(product.id, map);
  }

  @override
  Future<void> delete(String id) => _ds.delete(id);

  @override
  Future<void> updateStock(String id, int newStock) =>
      _ds.updateStock(id, newStock);
}
