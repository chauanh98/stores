import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';
import '../datasources/firebase/category_remote_data_source.dart';
import '../models/category_model.dart';

class CategoryRepositoryImpl implements CategoryRepository {
  CategoryRepositoryImpl(this._ds);

  final CategoryRemoteDataSource _ds;

  @override
  Stream<List<Category>> watchAll() => _ds.watchAll().map((list) {
        return list.map((m) => CategoryModel.fromMap(m).toEntity()).toList();
      });

  @override
  Future<List<Category>> fetchAll() async {
    final list = await _ds.fetchAll();
    return list.map((m) => CategoryModel.fromMap(m).toEntity()).toList();
  }

  @override
  Future<void> upsert(Category category) {
    final map = CategoryModel.fromEntity(category).toMap();
    return _ds.upsert(category.id, map);
  }

  @override
  Future<void> delete(String id) => _ds.delete(id);
}
