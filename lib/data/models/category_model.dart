import '../../domain/entities/category.dart';

class CategoryModel {
  final String id;
  final String name;
  final String? parentId;

  const CategoryModel({
    required this.id,
    required this.name,
    this.parentId,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'parentId': parentId,
      };

  factory CategoryModel.fromMap(Map<dynamic, dynamic> map) => CategoryModel(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        parentId: map['parentId'] as String?,
      );

  Category toEntity() => Category(
        id: id,
        name: name,
        parentId: parentId,
      );

  factory CategoryModel.fromEntity(Category c) => CategoryModel(
        id: c.id,
        name: c.name,
        parentId: c.parentId,
      );
}
