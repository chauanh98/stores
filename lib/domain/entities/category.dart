class Category {
  final String id;
  final String name;
  final String? parentId;

  const Category({
    required this.id,
    required this.name,
    this.parentId,
  });

  Category copyWith({
    String? id,
    String? name,
    String? parentId,
  }) =>
      Category(
        id: id ?? this.id,
        name: name ?? this.name,
        parentId: parentId ?? this.parentId,
      );
}
