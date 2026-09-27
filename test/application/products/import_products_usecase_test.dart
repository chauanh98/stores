import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/products/usecases/import_products_usecase.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/transaction_type.dart';
import 'package:stores/domain/repositories/category_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';

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

class _FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  @override
  Future<void> record(InventoryTransaction tx) async {
    transactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) {
    return Stream.value(
        transactions.where((t) => t.productId == productId).toList());
  }

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
      DateTime start, DateTime end,
      {String? storeId}) {
    return Stream.value(transactions
        .where((t) => t.type == TransactionType.import)
        .toList());
  }
}

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

void main() {
  group('ImportProductsUseCase Tests', () {
    late _FakeProductRepository productRepo;
    late _FakeInventoryRepository inventoryRepo;
    late _FakeCategoryRepository categoryRepo;
    late ImportProductsUseCase useCase;

    setUp(() {
      productRepo = _FakeProductRepository();
      inventoryRepo = _FakeInventoryRepository();
      categoryRepo = _FakeCategoryRepository();
      useCase = ImportProductsUseCase(
        productRepository: productRepo,
        inventoryRepository: inventoryRepo,
        categoryRepository: categoryRepo,
      );
    });

    test('Empty products list returns empty ImportResult', () async {
      final result = await useCase.execute(
        products: [],
        targetStoreId: 'store_001',
      );

      expect(result.total, 0);
      expect(result.added, 0);
      expect(result.updated, 0);
      expect(result.skipped, 0);
      expect(result.errors, 0);
      expect(result.isSuccess, isTrue);
      expect(result.hasErrors, isFalse);
    });

    test('New product insertion records stock and logs import transaction',
        () async {
      const newProduct = Product(
        id: 'prod_new_001',
        name: 'Bàn phím cơ',
        code: 'KB01',
        price: 500000,
        costPrice: 350000,
        branchStocks: {'store_001': 15},
        category: 'Phụ kiện',
      );

      final result = await useCase.execute(
        products: [newProduct],
        targetStoreId: 'store_001',
      );

      expect(result.total, 1);
      expect(result.added, 1);
      expect(result.updated, 0);
      expect(result.errors, 0);

      final stored = await productRepo.fetchById('prod_new_001');
      expect(stored, isNotNull);
      expect(stored!.name, 'Bàn phím cơ');
      expect(stored.branchStocks['store_001'], 15);

      // Verify inventory transaction was recorded
      expect(inventoryRepo.transactions.length, 1);
      final tx = inventoryRepo.transactions.first;
      expect(tx.productId, 'prod_new_001');
      expect(tx.type, TransactionType.import);
      expect(tx.quantity, 15);
      expect(tx.storeId, 'store_001');
      expect(tx.importPrice, 350000);
    });

    test('New product with 0 stock does not create import transaction',
        () async {
      const newProduct = Product(
        id: 'prod_zero_001',
        name: 'Chuột không dây',
        code: 'MS01',
        price: 200000,
        costPrice: 150000,
        branchStocks: {'store_001': 0},
        category: 'Phụ kiện',
      );

      final result = await useCase.execute(
        products: [newProduct],
        targetStoreId: 'store_001',
      );

      expect(result.added, 1);
      expect(inventoryRepo.transactions, isEmpty);
    });

    test(
        'Duplicate product by code updates basic info but strictly preserves branchStocks and imageUrl',
        () async {
      // Pre-existing product in store
      const existing = Product(
        id: 'prod_existing_10',
        name: 'iPhone 15 128GB Cũ',
        code: 'IP15-128',
        price: 18000000,
        costPrice: 15000000,
        branchStocks: {'store_001': 5, 'store_002': 8},
        category: 'Điện thoại',
        imageUrl: 'https://images.example.com/iphone15_original.jpg',
        images: ['https://images.example.com/iphone15_original.jpg'],
        unit: 'Chiếc',
        description: 'Máy đẹp 99%',
      );
      await productRepo.upsert(existing);

      // Imported product with modified price/name/unit/cat but Excel stock = 999 and empty image
      const imported = Product(
        id: 'prod_excel_diff_id',
        name: 'iPhone 15 128GB Mới 100%',
        code: 'ip15-128', // Case-insensitive match!
        price: 19500000,
        costPrice: 16000000,
        branchStocks: {'store_001': 999, 'store_002': 999},
        category: 'Điện thoại cao cấp',
        category3Levels: 'Điện thoại >> Apple >> iPhone 15',
        unit: 'Máy',
        description: 'Hàng chính hãng VN/A',
        imageUrl: '', // Blank in Excel
        images: [],
      );

      final result = await useCase.execute(
        products: [imported],
        targetStoreId: 'store_001',
      );

      expect(result.total, 1);
      expect(result.updated, 1);
      expect(result.added, 0);
      expect(result.errors, 0);

      final stored = await productRepo.fetchById('prod_existing_10');
      expect(stored, isNotNull);

      // 1. Basic fields updated:
      expect(stored!.name, 'iPhone 15 128GB Mới 100%');
      expect(stored.price, 19500000);
      expect(stored.costPrice, 16000000);
      expect(stored.unit, 'Máy');
      expect(stored.description, 'Hàng chính hãng VN/A');
      expect(stored.category3Levels, 'Điện thoại >> Apple >> iPhone 15');

      // 2. CRITICAL PRESERVATION:
      // branchStocks must remain EXACTLY as it was before import (5 and 8)
      expect(stored.branchStocks['store_001'], 5);
      expect(stored.branchStocks['store_002'], 8);
      // imageUrl must NOT be wiped out by Excel blank
      expect(stored.imageUrl,
          'https://images.example.com/iphone15_original.jpg');
      expect(stored.images,
          ['https://images.example.com/iphone15_original.jpg']);

      // No new inventory transactions recorded for duplicate update
      expect(inventoryRepo.transactions, isEmpty);
    });

    test('Duplicate product by id updates info and preserves existing stock',
        () async {
      const existing = Product(
        id: 'PROD_MATCH_ID',
        name: 'Tai nghe Bluetooth',
        code: 'TN01',
        price: 300000,
        costPrice: 200000,
        branchStocks: {'store_001': 22},
        category: 'Âm thanh',
      );
      await productRepo.upsert(existing);

      const imported = Product(
        id: 'prod_match_id', // lowercase match
        name: 'Tai nghe Bluetooth TWS Pro',
        code: 'TN01_V2',
        price: 350000,
        costPrice: 220000,
        branchStocks: {'store_001': 100},
        category: 'Âm thanh',
      );

      final result = await useCase.execute(
        products: [imported],
        targetStoreId: 'store_001',
      );

      expect(result.updated, 1);
      expect(result.added, 0);

      final stored = await productRepo.fetchById('PROD_MATCH_ID');
      expect(stored!.name, 'Tai nghe Bluetooth TWS Pro');
      expect(stored.branchStocks['store_001'], 22); // preserved
    });

    test('Accepts new image if existing product had no image', () async {
      const existing = Product(
        id: 'prod_no_img',
        name: 'Cáp sạc Type-C',
        code: 'CAP-TC',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'store_001': 10},
        category: 'Phụ kiện',
        imageUrl: null,
      );
      await productRepo.upsert(existing);

      const imported = Product(
        id: 'prod_no_img',
        name: 'Cáp sạc Type-C 1m',
        code: 'CAP-TC',
        price: 55000,
        costPrice: 32000,
        branchStocks: {'store_001': 50},
        category: 'Phụ kiện',
        imageUrl: 'https://images.example.com/cap_tc.png',
        images: ['https://images.example.com/cap_tc.png'],
      );

      final result = await useCase.execute(
        products: [imported],
        targetStoreId: 'store_001',
      );

      expect(result.updated, 1);
      final stored = await productRepo.fetchById('prod_no_img');
      expect(stored!.imageUrl, 'https://images.example.com/cap_tc.png');
      expect(stored.branchStocks['store_001'], 10); // preserved
    });

    test('Harvests 3-level categories and syncs to CategoryRepository',
        () async {
      const p1 = Product(
        id: 'p_cat_1',
        name: 'Laptop Dell XPS 13',
        code: 'XPS13',
        price: 30000000,
        costPrice: 25000000,
        branchStocks: {'store_001': 2},
        category: 'Laptop',
        category3Levels: 'Máy tính >> Laptop >> Dell',
      );

      final result = await useCase.execute(
        products: [p1],
        targetStoreId: 'store_001',
      );

      expect(result.added, 1);

      // Verify categories were harvested into repository
      final cats = await categoryRepo.fetchAll();
      expect(cats.any((c) => c.name == 'Máy tính'), isTrue);
      expect(cats.any((c) => c.name == 'Laptop'), isTrue);
      expect(cats.any((c) => c.name == 'Dell'), isTrue);
    });

    test('Summary string matches standard format', () async {
      const existing = Product(
        id: 'p_sum_1',
        name: 'Product 1',
        code: 'P01',
        price: 100,
        costPrice: 80,
        branchStocks: {'store_001': 10},
        category: 'Test',
      );
      await productRepo.upsert(existing);

      const p1 = Product(
        id: 'p_sum_1',
        name: 'Product 1 Updated',
        code: 'P01',
        price: 120,
        costPrice: 90,
        branchStocks: {'store_001': 50},
        category: 'Test',
      );

      const p2 = Product(
        id: 'p_sum_2',
        name: 'Product 2 New',
        code: 'P02',
        price: 200,
        costPrice: 150,
        branchStocks: {'store_001': 5},
        category: 'Test',
      );

      final result = await useCase.execute(
        products: [p1, p2],
        targetStoreId: 'store_001',
      );

      expect(result.total, 2);
      expect(result.updated, 1);
      expect(result.added, 1);
      expect(result.skipped, 0);
      expect(result.errors, 0);
      expect(
        result.toSummaryString(),
        'Tổng số dòng: 2 | Thêm mới: 1 | Cập nhật: 1 | Bỏ qua: 0 | Lỗi: 0',
      );
    });
  });
}
