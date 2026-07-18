import '../entities/category.dart';

abstract class CategoryRepository {
  Stream<List<Category>> watchAll();

  Future<List<Category>> fetchAll();

  Future<void> upsert(Category category);

  Future<void> delete(String id);
}
