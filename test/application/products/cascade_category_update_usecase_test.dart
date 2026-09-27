import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/usecases/cascade_category_update_usecase.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/repositories/category_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';

class _FakeCategoryRepository implements CategoryRepository {
  final Map<String, Category> storage = {};

  _FakeCategoryRepository([List<Category> initial = const []]) {
    for (final c in initial) {
      storage[c.id] = c;
    }
  }

  @override
  Stream<List<Category>> watchAll() => Stream.value(storage.values.toList());

  @override
  Future<List<Category>> fetchAll() async => storage.values.toList();

  @override
  Future<void> upsert(Category category) async {
    storage[category.id] = category;
  }

  @override
  Future<void> delete(String id) async {
    storage.remove(id);
  }
}

class _FakeProductRepository implements ProductRepository {
  final Map<String, Product> storage = {};

  _FakeProductRepository([List<Product> initial = const []]) {
    for (final p in initial) {
      storage[p.id] = p;
    }
  }

  @override
  Stream<List<Product>> watchAll() => Stream.value(storage.values.toList());

  @override
  Future<List<Product>> fetchAll() async => storage.values.toList();

  @override
  Future<Product?> fetchById(String id) async => storage[id];

  @override
  Future<void> upsert(Product product) async {
    storage[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    storage.remove(id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final p = storage[id];
    if (p != null) {
      storage[id] = p.copyWith(branchStocks: {'store_001': newStock});
    }
  }
}

void main() {
  group('CascadeCategoryUpdateUseCase Tests', () {
    late _FakeCategoryRepository categoryRepo;
    late _FakeProductRepository productRepo;
    late CascadeCategoryUpdateUseCase useCase;

    const rootBanAn = Category(id: 'ban_an', name: 'Bàn ăn');
    const childBanAnBen = Category(
      id: 'ban_an_ban_an_ben',
      name: 'Bàn ăn bên',
      parentId: 'ban_an',
    );
    const childBanAnCabin = Category(
      id: 'ban_an_cabin',
      name: 'Bàn ăn cabin',
      parentId: 'ban_an',
    );
    const rootGiuongGo = Category(id: 'giuong_go', name: 'Giường gỗ');
    const rootNoiThat = Category(id: 'noi_that', name: 'Nội thất phòng ăn');

    late List<Category> allCategories;
    late List<Product> initialProducts;

    setUp(() {
      allCategories = [
        rootBanAn,
        childBanAnBen,
        childBanAnCabin,
        rootGiuongGo,
        rootNoiThat,
      ];

      initialProducts = [
        // Product 1 (SP000771 KiotViet style): root category, multi-level c3
        const Product(
          id: 'sp_000771',
          name: 'Bàn ăn bên nguyên khối - chân vuông - 8 ghế đại tựa liền',
          code: 'SP000771',
          price: 25000000,
          costPrice: 20000000,
          branchStocks: {'store_001': 10},
          category: 'Bàn ăn',
          category3Levels: 'Bàn ăn>>Bàn ăn bên',
        ),
        // Product 2 (Flutter UI style): leaf category name, spaced >> delimiter
        const Product(
          id: 'prod_leaf_style',
          name: 'Bàn ăn bên gỗ gõ đỏ 6 ghế',
          code: 'BAB02',
          price: 18000000,
          costPrice: 14000000,
          branchStocks: {'store_001': 5},
          category: 'Bàn ăn bên',
          category3Levels: 'Bàn ăn >> Bàn ăn bên',
        ),
        // Product 3: Sibling subcategory
        const Product(
          id: 'prod_sibling',
          name: 'Bàn ăn cabin 4 ghế',
          code: 'BAC01',
          price: 3500000,
          costPrice: 2800000,
          branchStocks: {'store_001': 8},
          category: 'Bàn ăn',
          category3Levels: 'Bàn ăn >> Bàn ăn cabin',
        ),
        // Product 4: Product directly in root category
        const Product(
          id: 'prod_root',
          name: 'Bàn ăn mẫu chung không phân loại',
          code: 'BA00',
          price: 5000000,
          costPrice: 4000000,
          branchStocks: {'store_001': 2},
          category: 'Bàn ăn',
          category3Levels: 'Bàn ăn',
        ),
        // Product 5: In completely different category
        const Product(
          id: 'prod_other',
          name: 'Giường ngủ gỗ sồi 1m8',
          code: 'GG01',
          price: 9000000,
          costPrice: 7000000,
          branchStocks: {'store_001': 3},
          category: 'Giường gỗ',
          category3Levels: 'Giường gỗ',
        ),
      ];

      categoryRepo = _FakeCategoryRepository(allCategories);
      productRepo = _FakeProductRepository(initialProducts);

      useCase = CascadeCategoryUpdateUseCase(
        categoryRepository: categoryRepo,
        productRepository: productRepo,
        currentStoreId: 'store_001',
      );
    });

    test('1. Renaming a child category cascades to all matching products without touching siblings', () async {
      final result = await useCase.execute(
        targetCategory: childBanAnBen,
        newName: 'Bàn ăn gỗ bên',
        newParentId: childBanAnBen.parentId,
        allCategories: allCategories,
        currentProducts: initialProducts,
      );

      // Exactly 2 products belong to Bàn ăn bên (SP000771 and prod_leaf_style)
      expect(result.updatedProductsCount, equals(2));
      expect(result.updatedCategory.name, equals('Bàn ăn gỗ bên'));

      // Check SP000771 in repo
      final p1 = await productRepo.fetchById('sp_000771');
      expect(p1, isNotNull);
      expect(p1!.category3Levels, equals('Bàn ăn >> Bàn ăn gỗ bên'));
      expect(p1.category, equals('Bàn ăn')); // Root name stays unchanged

      // Check prod_leaf_style in repo
      final p2 = await productRepo.fetchById('prod_leaf_style');
      expect(p2, isNotNull);
      expect(p2!.category, equals('Bàn ăn gỗ bên')); // Leaf name updated
      expect(p2.category3Levels, equals('Bàn ăn >> Bàn ăn gỗ bên'));

      // Check prod_sibling was NOT modified
      final p3 = await productRepo.fetchById('prod_sibling');
      expect(p3, isNotNull);
      expect(p3!.category, equals('Bàn ăn'));
      expect(p3.category3Levels, equals('Bàn ăn >> Bàn ăn cabin'));

      // Check prod_other was NOT modified
      final p5 = await productRepo.fetchById('prod_other');
      expect(p5, isNotNull);
      expect(p5!.category, equals('Giường gỗ'));

      // Check category in categoryRepo was updated
      final updatedCat = (await categoryRepo.fetchAll())
          .firstWhere((c) => c.id == childBanAnBen.id);
      expect(updatedCat.name, equals('Bàn ăn gỗ bên'));
    });

    test('2. Renaming a root category updates root products and all descendant paths and root names', () async {
      final result = await useCase.execute(
        targetCategory: rootBanAn,
        newName: 'Bàn ăn gia đình',
        newParentId: null,
        allCategories: allCategories,
        currentProducts: initialProducts,
      );

      // All 4 products under Bàn ăn (p1, p2, p3, prod_root) should be updated
      expect(result.updatedProductsCount, equals(4));
      expect(result.updatedCategory.name, equals('Bàn ăn gia đình'));

      // SP000771: root category name and path updated
      final p1 = await productRepo.fetchById('sp_000771');
      expect(p1!.category, equals('Bàn ăn gia đình'));
      expect(p1.category3Levels, equals('Bàn ăn gia đình >> Bàn ăn bên'));

      // prod_leaf_style: leaf name stays 'Bàn ăn bên', root path prefix updated
      final p2 = await productRepo.fetchById('prod_leaf_style');
      expect(p2!.category, equals('Bàn ăn bên'));
      expect(p2.category3Levels, equals('Bàn ăn gia đình >> Bàn ăn bên'));

      // prod_sibling: root name updated, path prefix updated
      final p3 = await productRepo.fetchById('prod_sibling');
      expect(p3!.category, equals('Bàn ăn gia đình'));
      expect(p3.category3Levels, equals('Bàn ăn gia đình >> Bàn ăn cabin'));

      // prod_root: directly in root category
      final p4 = await productRepo.fetchById('prod_root');
      expect(p4!.category, equals('Bàn ăn gia đình'));
      expect(p4.category3Levels, equals('Bàn ăn gia đình'));

      // Other category untouched
      final p5 = await productRepo.fetchById('prod_other');
      expect(p5!.category, equals('Giường gỗ'));
    });

    test('3. Changing parent of a subcategory updates hierarchy path for all associated products', () async {
      final result = await useCase.execute(
        targetCategory: childBanAnBen,
        newName: childBanAnBen.name, // name unchanged
        newParentId: rootNoiThat.id, // moved from Bàn ăn to Nội thất phòng ăn
        allCategories: allCategories,
        currentProducts: initialProducts,
      );

      expect(result.updatedProductsCount, equals(2));
      expect(result.updatedCategory.parentId, equals(rootNoiThat.id));

      final p1 = await productRepo.fetchById('sp_000771');
      expect(p1!.category, equals('Nội thất phòng ăn')); // New root name
      expect(p1.category3Levels, equals('Nội thất phòng ăn >> Bàn ăn bên'));

      final p2 = await productRepo.fetchById('prod_leaf_style');
      expect(p2!.category, equals('Bàn ăn bên'));
      expect(p2.category3Levels, equals('Nội thất phòng ăn >> Bàn ăn bên'));
    });

    test('4. Renaming category with zero products updates category and returns count 0', () async {
      const emptyCat = Category(id: 'empty_cat', name: 'Nhóm trống');
      final categoriesWithEmpty = [...allCategories, emptyCat];

      final result = await useCase.execute(
        targetCategory: emptyCat,
        newName: 'Nhóm mới đổi',
        newParentId: null,
        allCategories: categoriesWithEmpty,
        currentProducts: initialProducts,
      );

      expect(result.updatedProductsCount, equals(0));
      expect(result.updatedCategory.name, equals('Nhóm mới đổi'));

      final catInRepo = (await categoryRepo.fetchAll())
          .firstWhere((c) => c.id == emptyCat.id);
      expect(catInRepo.name, equals('Nhóm mới đổi'));
    });

    test('5. Dynamic harvesting after cascade update does NOT recover old category name', () async {
      // Step A: Rename Bàn ăn bên -> Bàn ăn gỗ bên
      await useCase.execute(
        targetCategory: childBanAnBen,
        newName: 'Bàn ăn gỗ bên',
        newParentId: childBanAnBen.parentId,
        allCategories: allCategories,
        currentProducts: initialProducts,
      );

      // Step B: Read all products from repository (they now have the new category)
      final latestProducts = await productRepo.fetchAll();
      final latestCategories = await categoryRepo.fetchAll();

      // Step C: Run dynamic harvesting
      final harvested = harvestCategoriesFromProducts(
        latestCategories,
        latestProducts,
      );

      final allNamesLower =
          harvested.map((c) => c.name.trim().toLowerCase()).toSet();

      // Old name "bàn ăn bên" should NOT exist anywhere in harvested categories
      expect(allNamesLower.contains('bàn ăn bên'), isFalse,
          reason: 'Old category name must not be re-harvested from products');

      // New name "bàn ăn gỗ bên" MUST exist
      expect(allNamesLower.contains('bàn ăn gỗ bên'), isTrue,
          reason: 'New category name must be present in harvested categories');
    });
  });
}
