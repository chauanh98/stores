import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/vietnamese_text_helper.dart';
import '../../data/datasources/firebase/category_remote_data_source.dart';
import '../../data/repositories/category_repository_impl.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/product.dart';
import '../../domain/repositories/category_repository.dart';

final categoryRemoteDataSourceProvider =
    Provider<CategoryRemoteDataSource>((ref) {
  try {
    return CategoryRemoteDataSource(FirebaseDatabase.instance);
  } catch (_) {
    return CategoryRemoteDataSource();
  }
});

final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  final ds = ref.watch(categoryRemoteDataSourceProvider);
  return CategoryRepositoryImpl(ds);
});

// A provider that streams all categories from Firebase and auto-seeds them if empty
final categoryListProvider = StreamProvider.autoDispose<List<Category>>((ref) {
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

    // Seed with standardized 2-root hierarchy directly
    // (dynamic harvesting already extracts categories from products at runtime)
    // 1. Root: Đồ gỗ & Nội thất
    const noiThat = Category(id: 'noi_that', name: 'Đồ gỗ & Nội thất');
    categoriesToSeed['noi_that'] = noiThat;

    final noiThatSubs = [
      'Ghế cao đốt nhang gỗ',
      'Trường kỷ',
      'Tủ thờ',
      'Văn phòng',
      'Xích đu',
    ];
    for (final name in noiThatSubs) {
      final id = generateCategoryId(name, 'noi_that');
      categoriesToSeed[id] = Category(id: id, name: name, parentId: 'noi_that');
    }

    final tuThoId = generateCategoryId('Tủ thờ', 'noi_that');
    final tuThoThaoLaoId = generateCategoryId('Tủ thờ thao lao', tuThoId);
    categoriesToSeed[tuThoThaoLaoId] = Category(
      id: tuThoThaoLaoId,
      name: 'Tủ thờ thao lao',
      parentId: tuThoId,
    );

    final xichDuId = generateCategoryId('Xích đu', 'noi_that');
    final xichDuSatId = generateCategoryId('Xích đu sắt', xichDuId);
    categoriesToSeed[xichDuSatId] = Category(
      id: xichDuSatId,
      name: 'Xích đu sắt',
      parentId: xichDuId,
    );
    final sat1122Id = generateCategoryId('sat 1122', xichDuSatId);
    categoriesToSeed[sat1122Id] = Category(
      id: sat1122Id,
      name: 'sat 1122',
      parentId: xichDuSatId,
    );

    // 2. Root: Thiết bị điện tử
    const thietBiDienTu =
        Category(id: 'thiet_bi_dien_tu', name: 'Thiết bị điện tử');
    categoriesToSeed['thiet_bi_dien_tu'] = thietBiDienTu;

    final thietBiSubs = [
      'Smartphone',
      'Laptop',
      'Tablet',
    ];
    for (final name in thietBiSubs) {
      final id = generateCategoryId(name, 'thiet_bi_dien_tu');
      categoriesToSeed[id] =
          Category(id: id, name: name, parentId: 'thiet_bi_dien_tu');
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
String generateCategoryId(String name, String? parentId) {
  final trimmed = name.trim();
  if (parentId == null) {
    if (trimmed.toLowerCase() == 'đồ gỗ & nội thất' ||
        trimmed.toLowerCase() == 'do go & noi that') {
      return 'noi_that';
    }
    if (trimmed.toLowerCase() == 'thiết bị điện tử' ||
        trimmed.toLowerCase() == 'thiet bi dien tu') {
      return 'thiet_bi_dien_tu';
    }
  }
  final unaccented = VietnameseTextHelper.normalizeUnaccented(name);
  final cleanName = unaccented
      .toLowerCase()
      .trim()
      .replaceAll(RegExp(r'[^a-z0-9_]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final slug = cleanName.isEmpty ? 'cat' : cleanName;
  if (parentId != null) {
    return '${parentId}_$slug';
  }
  return slug;
}

/// Dynamic Category Harvesting:
/// Scans products to extract category hierarchy and merges them into base categories.
/// Uses a two-pass algorithm to ensure multi-level paths (with parents/children) are established
/// before single-level categories, preventing duplicate root nodes regardless of product order.
/// If any new categories are discovered, optionally syncs them to Firebase in the background.
List<Category> harvestCategoriesFromProducts(
  List<Category> baseCategories,
  List<Product> products, {
  CategoryRepository? syncRepo,
}) {
  if (products.isEmpty) return baseCategories;

  // Map existing categories by id
  final Map<String, Category> categoryMap = {
    for (final c in baseCategories) c.id: c,
  };

  // Quick lookup by parentId + lowercase name, and all known names
  final Map<String, String> nameAndParentToId = {};
  final Set<String> allKnownNamesLower = {};
  for (final c in baseCategories) {
    final nameLower = c.name.trim().toLowerCase();
    final key = '${c.parentId ?? ""}|$nameLower';
    nameAndParentToId[key] = c.id;
    allKnownNamesLower.add(nameLower);
  }

  final List<Category> newlyHarvested = [];

  // Partition products into multi-level paths and single-level paths.
  // Multi-level paths must be processed in Pass 1 to build parent-child trees first.
  final multiLevelPaths = <List<String>>[];
  final singleLevelPaths = <String>[];

  for (final p in products) {
    final c3 = p.category3Levels?.trim() ?? '';
    final cat = p.category.trim();
    final path = c3.isNotEmpty
        ? c3
        : (cat.contains('>>') || cat.contains('>') || baseCategories.isEmpty
            ? cat
            : '');
    if (path.isEmpty ||
        path.toLowerCase() == 'all' ||
        path.toLowerCase() == 'tất cả') {
      continue;
    }

    final parts = path
        .split(RegExp(r'>>|>'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    if (parts.isEmpty) continue;

    if (parts.length > 1) {
      multiLevelPaths.add(parts);
    } else {
      singleLevelPaths.add(parts[0]);
    }
  }

  // Pass 1: Process all multi-level paths to establish hierarchy
  for (final parts in multiLevelPaths) {
    String? currentParentId;
    for (int i = 0; i < parts.length; i++) {
      final partName = parts[i];
      final partNameLower = partName.toLowerCase();
      final lookupKey = '${currentParentId ?? ""}|$partNameLower';

      final existingId = nameAndParentToId[lookupKey];
      if (existingId == null) {
        final generatedId = generateCategoryId(partName, currentParentId);
        if (!categoryMap.containsKey(generatedId)) {
          final newCat = Category(
            id: generatedId,
            name: partName,
            parentId: currentParentId,
          );
          categoryMap[generatedId] = newCat;
          nameAndParentToId[lookupKey] = generatedId;
          allKnownNamesLower.add(partNameLower);
          newlyHarvested.add(newCat);
          currentParentId = generatedId;
        } else {
          nameAndParentToId[lookupKey] = generatedId;
          currentParentId = generatedId;
        }
      } else {
        currentParentId = existingId;
      }
    }
  }

  // Pass 2: Process single-level paths, skipping any whose name already exists in the tree
  for (final name in singleLevelPaths) {
    final nameLower = name.toLowerCase();
    if (allKnownNamesLower.contains(nameLower)) {
      continue;
    }
    final lookupKey = '|$nameLower';
    final generatedId = generateCategoryId(name, null);
    if (!categoryMap.containsKey(generatedId)) {
      final newCat = Category(
        id: generatedId,
        name: name,
        parentId: null,
      );
      categoryMap[generatedId] = newCat;
      nameAndParentToId[lookupKey] = generatedId;
      allKnownNamesLower.add(nameLower);
      newlyHarvested.add(newCat);
    } else {
      nameAndParentToId[lookupKey] = generatedId;
    }
  }

  // Background sync newly harvested categories to Firebase RTDB if a repo is provided
  if (syncRepo != null && newlyHarvested.isNotEmpty) {
    for (final newCat in newlyHarvested) {
      syncRepo.upsert(newCat).catchError((_) {});
    }
  }

  // Preserve referential identity if nothing was added or deduplicated
  if (newlyHarvested.isEmpty && categoryMap.length == baseCategories.length) {
    return baseCategories;
  }

  return categoryMap.values.toList();
}
