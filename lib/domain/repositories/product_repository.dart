import '../entities/product.dart';

abstract class ProductRepository {
  Stream<List<Product>> watchAll();

  Future<Product?> fetchById(String id);

  Future<void> upsert(Product product);

  Future<void> delete(String id);

  Future<void> updateStock(String id, int newStock);
}
