import '../../domain/entities/product.dart';
import '../../domain/repositories/product_repository.dart';
import '../datasources/firebase/product_remote_data_source.dart';
import '../models/product_model.dart';

class ProductRepositoryImpl implements ProductRepository {
  ProductRepositoryImpl(this._ds);

  final ProductRemoteDataSource _ds;

  @override
  Stream<List<Product>> watchAll() => _ds.watchAll().map((list) {
    return list.map((m) {
      final model = ProductModel.fromMap(m);
      return Product(
        id: model.id,
        name: model.name,
        brand: model.brand,
        model: model.model,
        price: model.price,
        stock: model.stock,
        category: model.category,
      );
    }).toList();
  });

  @override
  Future<Product?> fetchById(String id) async {
    final m = await _ds.fetchById(id);
    if (m == null) return null;
    final model = ProductModel.fromMap(m);
    return Product(
      id: model.id,
      name: model.name,
      brand: model.brand,
      model: model.model,
      price: model.price,
      stock: model.stock,
      category: model.category,
    );
  }

  @override
  Future<void> upsert(Product product) {
    final map = ProductModel(
      id: product.id,
      name: product.name,
      brand: product.brand,
      model: product.model,
      price: product.price,
      stock: product.stock,
      category: product.category,
    ).toMap();
    return _ds.upsert(product.id, map);
  }

  @override
  Future<void> delete(String id) => _ds.delete(id);

  @override
  Future<void> updateStock(String id, int newStock) => _ds.updateStock(id, newStock);
}