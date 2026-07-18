import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/datasources/firebase/category_remote_data_source.dart';
import '../../data/repositories/category_repository_impl.dart';
import '../../domain/entities/category.dart';
import '../../domain/repositories/category_repository.dart';

final categoryRemoteDataSourceProvider =
    Provider<CategoryRemoteDataSource>((ref) {
  return CategoryRemoteDataSource(FirebaseDatabase.instance);
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  final ds = ref.watch(categoryRemoteDataSourceProvider);
  return CategoryRepositoryImpl(ds);
});

// A provider that streams all categories from Firebase and auto-seeds them if empty
final categoryListProvider = StreamProvider<List<Category>>((ref) {
  final repo = ref.watch(categoryRepositoryProvider);

  // Set up stream listener
  return repo.watchAll().map((categories) {
    if (categories.isEmpty) {
      // Trigger async seeding
      _seedCategories(ref);
    }
    return categories;
  });
});

// Helper function to seed categories
Future<void> _seedCategories(Ref ref) async {
  try {
    final repo = ref.read(categoryRepositoryProvider);
    final Map<String, Category> categoriesToSeed = {};

    // Fetch all stores data from Firebase to scan categories across all stores
    final storesSnap = await FirebaseDatabase.instance.ref('stores').get();
    if (storesSnap.exists && storesSnap.value != null) {
      final storesMap = Map<String, dynamic>.from(storesSnap.value as Map);
      for (final entry in storesMap.entries) {
        if (entry.key == 'accounts') continue;
        final storeData = Map<String, dynamic>.from(entry.value as Map);
        final productsData = storeData['products'];
        if (productsData == null) continue;

        final Map productsMap = productsData is List
            ? productsData.asMap()
            : Map.from(productsData as Map);

        for (final prodVal in productsMap.values) {
          if (prodVal == null) continue;
          final prodMap = Map.from(prodVal as Map);
          final path = (prodMap['category3Levels'] as String?) ??
              (prodMap['category'] as String?) ??
              '';
          if (path.isEmpty) continue;

          final parts = path.split('>>').map((e) => e.trim()).toList();
          String? parentId;

          for (int i = 0; i < parts.length; i++) {
            final partName = parts[i];
            final id = _generateCategoryId(partName, parentId);
            if (!categoriesToSeed.containsKey(id)) {
              categoriesToSeed[id] = Category(
                id: id,
                name: partName,
                parentId: parentId,
              );
            }
            parentId = id;
          }
        }
      }
    }

    // If still empty (no products in db), seed with original hardcoded app categories
    if (categoriesToSeed.isEmpty) {
      final defaultList = [
        'Smartphone',
        'Laptop',
        'Tablet',
        'Desktop',
        'Monitor',
        'Keyboard',
        'Mouse',
        'Headphone',
        'Speaker',
        'Camera',
        'Accessories',
        'Other'
      ];
      for (final name in defaultList) {
        final id = name.toLowerCase().replaceAll(' ', '_');
        categoriesToSeed[id] = Category(id: id, name: name);
      }
    }

    // Write to Firebase
    for (final cat in categoriesToSeed.values) {
      await repo.upsert(cat);
    }
  } catch (_) {
    // Fail silently on background seeding
  }
}

// Generate deterministic IDs based on name and parent ID to prevent duplicates
String _generateCategoryId(String name, String? parentId) {
  final cleanName =
      name.toLowerCase().trim().replaceAll(RegExp(r'[^a-z0-9_]'), '_');
  if (parentId != null) {
    return '${parentId}_$cleanName';
  }
  return cleanName;
}
