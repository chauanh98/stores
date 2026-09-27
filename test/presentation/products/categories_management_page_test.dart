import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/category_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/categories_management_page.dart';

class _FakeCategoryRepository implements CategoryRepository {
  final List<Category> categories;
  final List<Category> upserted = [];
  final List<String> deleted = [];
  final StreamController<List<Category>> _controller =
      StreamController<List<Category>>.broadcast();

  _FakeCategoryRepository(List<Category> initial)
      : categories = List.from(initial) {
    _emit();
  }

  void _emit() {
    _controller.add(List.unmodifiable(categories));
  }

  @override
  Stream<List<Category>> watchAll() async* {
    yield List.unmodifiable(categories);
    yield* _controller.stream;
  }

  @override
  Future<List<Category>> fetchAll() async => List.unmodifiable(categories);

  @override
  Future<void> upsert(Category category) async {
    upserted.add(category);
    final idx = categories.indexWhere((c) => c.id == category.id);
    if (idx >= 0) {
      categories[idx] = category;
    } else {
      categories.add(category);
    }
    _emit();
  }

  @override
  Future<void> delete(String id) async {
    deleted.add(id);
    categories.removeWhere((c) => c.id == id);
    _emit();
  }
}

class _TestProductRepository implements ProductRepository {
  final List<Product> products;
  final List<Product> upserted = [];

  _TestProductRepository(this.products);

  @override
  Stream<List<Product>> watchAll() => Stream.value(products);

  @override
  Future<List<Product>> fetchAll() async => products;

  @override
  Future<Product?> fetchById(String id) async => products
      .cast<Product?>()
      .firstWhere((p) => p?.id == id, orElse: () => null);

  @override
  Future<void> upsert(Product product) async {
    upserted.add(product);
  }

  @override
  Future<void> delete(String id) async {}

  @override
  Future<void> updateStock(String id, int newStock) async {}
}

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const adminUser = UserAccount(
    username: 'admin',
    displayName: 'Quản trị viên',
    role: 'admin',
    storeId: 'store_001',
  );

  final testCategories = [
    const Category(id: 'cat_beverage', name: 'Đồ uống'),
    const Category(
        id: 'cat_beer', name: 'Bia & Rượu', parentId: 'cat_beverage'),
    const Category(
        id: 'cat_softdrink', name: 'Nước ngọt', parentId: 'cat_beverage'),
    const Category(id: 'cat_food', name: 'Thực phẩm'),
  ];

  final testProducts = [
    const Product(
      id: 'p1',
      name: 'Bia Saigon',
      code: 'BSG',
      price: 15000,
      costPrice: 10000,
      branchStocks: {'b1': 10},
      category: 'Bia & Rượu',
      category3Levels: 'Đồ uống >> Bia & Rượu',
    ),
    const Product(
      id: 'p2',
      name: 'Nước ngọt Coca',
      code: 'COCA',
      price: 10000,
      costPrice: 7000,
      branchStocks: {'b1': 20},
      category: 'Nước ngọt',
      category3Levels: 'Đồ uống >> Nước ngọt',
    ),
    const Product(
      id: 'p3',
      name: 'Bánh gạo',
      code: 'BG',
      price: 25000,
      costPrice: 18000,
      branchStocks: {'b1': 5},
      category: 'Thực phẩm',
    ),
  ];

  Widget buildTestWidget({required _FakeCategoryRepository repo}) {
    return ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        categoryRepositoryProvider.overrideWithValue(repo),
        categoryListProvider.overrideWith((ref) => repo.watchAll()),
        productListProvider.overrideWith((ref) => Stream.value(testProducts)),
      ],
      child: const MaterialApp(
        home: CategoriesManagementPage(),
      ),
    );
  }

  testWidgets(
      'Displays categories tree view with correct product count badges',
      (tester) async {
    final repo = _FakeCategoryRepository(testCategories);

    await tester.pumpWidget(buildTestWidget(repo: repo));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('Quản lý nhóm hàng'), findsOneWidget);
    expect(find.text('Đồ uống'), findsOneWidget);
    expect(find.text('Thực phẩm'), findsOneWidget);

    // Root "Đồ uống" includes Bia & Rượu (1) + Nước ngọt (1) = 2 products
    expect(find.text('2 sản phẩm'), findsOneWidget);
    // "Thực phẩm" has 1 product
    expect(find.text('1 sản phẩm'), findsWidgets);
  });

  testWidgets('Search query filters category list dynamically',
      (tester) async {
    final repo = _FakeCategoryRepository(testCategories);

    await tester.pumpWidget(buildTestWidget(repo: repo));
    await tester.pump();
    await tester.pumpAndSettle();

    final searchField = find.byType(TextField);
    await tester.enterText(searchField, 'Bia');
    await tester.pumpAndSettle();

    expect(find.text('Bia & Rượu'), findsOneWidget);
    expect(find.text('Thực phẩm'), findsNothing);
  });

  testWidgets('Add root category creates and saves to repository',
      (tester) async {
    final repo = _FakeCategoryRepository(testCategories);

    await tester.pumpWidget(buildTestWidget(repo: repo));
    await tester.pump();
    await tester.pumpAndSettle();

    // Tap add root category button
    final addBtn = find.byKey(const Key('add_root_category_button'));
    await tester.tap(addBtn);
    await tester.pumpAndSettle();

    expect(find.text('Thêm nhóm hàng'), findsWidgets);

    // Enter name
    await tester.enterText(
        find.byKey(const Key('category_name_input')), 'Gia dụng');
    await tester.pumpAndSettle();

    // Save
    await tester.tap(find.byKey(const Key('save_category_button')));
    await tester.pumpAndSettle();

    expect(repo.upserted.any((c) => c.name == 'Gia dụng'), isTrue);
  });

  testWidgets('Add child category pre-selects parent category',
      (tester) async {
    final repo = _FakeCategoryRepository(testCategories);

    await tester.pumpWidget(buildTestWidget(repo: repo));
    await tester.pump();
    await tester.pumpAndSettle();

    // Tap quick add child button on cat_food
    final addChildBtn = find.byKey(const Key('add_child_category_cat_food'));
    await tester.tap(addChildBtn);
    await tester.pumpAndSettle();

    expect(find.text('Thêm nhóm con'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('category_name_input')), 'Bánh ngọt');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save_category_button')));
    await tester.pumpAndSettle();

    expect(
        repo.upserted.any(
            (c) => c.name == 'Bánh ngọt' && c.parentId == 'cat_food'),
        isTrue);
  });

  testWidgets('Edit category updates category name and parent',
      (tester) async {
    final repo = _FakeCategoryRepository(testCategories);

    await tester.pumpWidget(buildTestWidget(repo: repo));
    await tester.pump();
    await tester.pumpAndSettle();

    final editBtn = find.byKey(const Key('edit_category_cat_food'));
    await tester.tap(editBtn);
    await tester.pumpAndSettle();

    expect(find.text('Sửa nhóm hàng'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('edit_category_name_input')), 'Thực phẩm khô');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save_edit_category_button')));
    await tester.pumpAndSettle();

    expect(repo.upserted.any((c) => c.name == 'Thực phẩm khô'), isTrue);
  });

  testWidgets(
      'Delete category shows warning dialog when category has children and products',
      (tester) async {
    final repo = _FakeCategoryRepository(testCategories);

    await tester.pumpWidget(buildTestWidget(repo: repo));
    await tester.pump();
    await tester.pumpAndSettle();

    // Delete "Đồ uống" which has 2 children and 2 products
    final deleteBtn = find.byKey(const Key('delete_category_cat_beverage'));
    await tester.tap(deleteBtn);
    await tester.pumpAndSettle();

    expect(find.text('Xóa nhóm hàng'), findsOneWidget);
    expect(find.textContaining('Cảnh báo: Có 2 nhóm con trực thuộc!'),
        findsOneWidget);
    expect(
        find.textContaining('Cảnh báo: Có 2 sản phẩm đang thuộc nhóm này!'),
        findsOneWidget);

    // Confirm delete
    final confirmBtn =
        find.byKey(const Key('confirm_delete_category_button'));
    await tester.tap(confirmBtn);
    await tester.pumpAndSettle();

    expect(repo.deleted, contains('cat_beverage'));
  });

  testWidgets(
      'Edit category cascades update to products and displays product count snackbar',
      (tester) async {
    final catRepo = _FakeCategoryRepository(testCategories);
    final fakeProductRepo = _TestProductRepository(testProducts);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
        categoryRepositoryProvider.overrideWithValue(catRepo),
        categoryListProvider.overrideWith((ref) => catRepo.watchAll()),
        productListProvider.overrideWith((ref) => Stream.value(testProducts)),
        productRepositoryProvider.overrideWithValue(fakeProductRepo),
      ],
      child: const MaterialApp(
        home: CategoriesManagementPage(),
      ),
    ));
    await tester.pumpAndSettle();

    // Edit "Đồ uống" (has 2 products: p1 in 'Bia & Rượu', p2 in 'Nước ngọt')
    final editBtn = find.byKey(const Key('edit_category_cat_beverage'));
    await tester.tap(editBtn);
    await tester.pumpAndSettle();

    await tester.enterText(
        find.byKey(const Key('edit_category_name_input')), 'Thức uống giải khát');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('save_edit_category_button')));
    await tester.pumpAndSettle();

    // Verify snackbar displays cascaded update count
    expect(find.textContaining('Đã cập nhật nhóm hàng và 2 sản phẩm liên quan'),
        findsOneWidget);

    // Verify category repo received updated category
    expect(
        catRepo.upserted.any((c) => c.name == 'Thức uống giải khát'), isTrue);

    // Verify product repo received updated products with updated category3Levels
    expect(
        fakeProductRepo.upserted
            .any((p) => p.category3Levels?.contains('Thức uống giải khát') == true),
        isTrue);
  });
}

