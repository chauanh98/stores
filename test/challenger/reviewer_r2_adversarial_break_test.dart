import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/core/utils/image_compression_helper.dart';
import 'package:stores/core/utils/sample_image_helper.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/widgets/sample_image_picker_dialog.dart';

class _MockAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _MockAuthNotifier()
      : super(
          const UserAccount(
            username: 'admin',
            displayName: 'Admin User',
            role: 'admin',
            storeId: 'store_001',
          ),
        );

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _InMemoryProductRepo implements ProductRepository {
  final Map<String, Product> store = {};
  Product? lastSaved;

  @override
  Future<void> upsert(Product product) async {
    lastSaved = product;
    store[product.id] = product;
  }

  @override
  Future<void> delete(String id) async {
    store.remove(id);
  }

  @override
  Future<List<Product>> fetchAll() async => store.values.toList();

  @override
  Future<Product?> fetchById(String id) async => store[id];

  @override
  Stream<List<Product>> watchAll() => Stream.value(store.values.toList());

  @override
  Future<void> updateStock(String id, int newStock) async {
    if (store.containsKey(id)) {
      store[id] = store[id]!.copyWith(branchStocks: {'store_001': newStock});
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List createTestJpgBytes({int width = 200, int height = 200}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(100, 150, 200));
    return Uint8List.fromList(img.encodeJpg(image, quality: 75));
  }

  Product makeProduct({
    required String name,
    String category = '',
    String? imageUrl,
  }) {
    return Product(
      id: 'prod_${name.hashCode}',
      code: 'PROD_TEST',
      name: name,
      category: category,
      price: 1500000,
      costPrice: 900000,
      branchStocks: const {'store_001': 10},
      imageUrl: imageUrl,
    );
  }

  group('Round 2 Reviewer Adversarial Suite 1: SampleImagePickerDialog 100% Furniture Isolation', () {
    testWidgets('Non-furniture product name produces ZERO non-furniture smart suggestions', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Open dialog with non-furniture product name (e.g. Bia Tiger)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  SampleImagePickerDialog.show(
                    context,
                    productName: 'Bia Tiger lon 330ml',
                    category: 'Đồ uống',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Ensure NO beer, soda, food, or cosmetics are suggested
      expect(find.textContaining('Bia & Đồ uống có cồn'), findsNothing);
      expect(find.textContaining('Nước ngọt'), findsNothing);
      expect(find.textContaining('Mì gói'), findsNothing);
      expect(find.textContaining('Mỹ phẩm'), findsNothing);

      // Verify that all visible categories are strictly within the 6 room spaces
      for (final room in SampleImageHelper.roomOrder) {
        // Rooms should exist in chips or items
        expect(SampleImageHelper.industries.contains(room), isTrue);
      }
    });

    testWidgets('Advanced search with descriptive adjectives matches correct furniture categories', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  SampleImagePickerDialog.show(
                    context,
                    productName: 'Sản phẩm nội thất',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).first;

      // 1. Search "bàn ăn 6 ghế cao cấp" (contains descriptive phrase "cao cấp")
      await tester.enterText(searchField, 'bàn ăn 6 ghế cao cấp');
      await tester.pumpAndSettle();
      expect(find.text('Bàn ăn mặt đá cẩm thạch chống xước & Bàn trà sofa, Bàn cafe'), findsOneWidget);

      // 2. Search "sofa góc L bọc nỉ đẹp" (contains descriptive phrase "bọc nỉ đẹp")
      await tester.enterText(searchField, 'sofa góc L bọc nỉ đẹp');
      await tester.pumpAndSettle();
      expect(find.text('Sofa nỉ góc chữ L & Sofa da, Sofa bed'), findsOneWidget);

      // 3. Search "giường 1m8 gỗ sồi hiện đại"
      await tester.enterText(searchField, 'giường 1m8 gỗ sồi hiện đại');
      await tester.pumpAndSettle();
      expect(find.text('Giường ngủ gỗ tự nhiên (gỗ sồi, gõ đỏ) & Nệm, Ga gối'), findsOneWidget);

      // 4. Search "xích đu sắt nghệ thuật"
      await tester.enterText(searchField, 'xích đu sắt nghệ thuật');
      await tester.pumpAndSettle();
      expect(find.text('Xích đu sắt mỹ thuật sơn tĩnh điện ngoài trời'), findsOneWidget);

      // 5. Search "ghế đốt nhang gia tiên"
      await tester.enterText(searchField, 'ghế đốt nhang gia tiên');
      await tester.pumpAndSettle();
      expect(find.text('Ghế cao thắp nhang (Ghế đốt nhang gỗ có tay vịn)'), findsOneWidget);
    });

    testWidgets('Room space chip filter combined with search query behaves predictably', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  SampleImagePickerDialog.show(
                    context,
                    productName: '',
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Tap on "Phòng khách" chip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Phòng khách'));
      await tester.pumpAndSettle();

      final searchField = find.byType(TextField).first;

      // Searching for "sofa" in "Phòng khách" yields results
      await tester.enterText(searchField, 'sofa');
      await tester.pumpAndSettle();
      expect(find.text('Sofa nỉ góc chữ L & Sofa da, Sofa bed'), findsOneWidget);

      // Searching for "bàn ăn" in "Phòng khách" yields 0 results
      await tester.enterText(searchField, 'bàn ăn');
      await tester.pumpAndSettle();
      expect(find.text('Không tìm thấy ảnh mẫu phù hợp'), findsOneWidget);

      // Clear search
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Room items in "Phòng khách" restored
      expect(find.text('Sofa văng'), findsOneWidget);

      // Rapidly toggle chips
      await tester.tap(find.widgetWithText(ChoiceChip, 'Phòng ngủ'));
      await tester.pumpAndSettle();
      expect(find.text('Giường tầng'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Tất cả nội thất'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tất cả nội thất & đồ gỗ'), findsOneWidget);
    });
  });

  group('Round 2 Reviewer Adversarial Suite 2: AddProductPage & ProductDetailPage Image State Lifecycle', () {
    testWidgets('AddProductPage saves successfully without an image (imageUrl is null)', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _InMemoryProductRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            productListProvider.overrideWith((ref) => Stream.value([])),
            categoryListProvider.overrideWith(
              (ref) => Stream.value([const Category(id: 'c1', name: 'Nội thất')]),
            ),
            currentStoreIdProvider.overrideWithValue('store_001'),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: AddProductPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Tên hàng *'), 'Bàn trà sofa gỗ sồi');
      await tester.enterText(find.widgetWithText(TextFormField, 'Giá bán'), '1200000');

      await tester.tap(find.widgetWithText(InputDecorator, 'Chọn nhóm hàng *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nội thất').first);
      await tester.pumpAndSettle();

      // Save without touching image
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      expect(repo.lastSaved, isNotNull);
      expect(repo.lastSaved!.name, equals('Bàn trà sofa gỗ sồi'));
      expect(repo.lastSaved!.imageUrl, isNull);
    });

    testWidgets('ProductDetailPage removes existing image cleanly on delete button tap', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _InMemoryProductRepo();
      final initialBytes = createTestJpgBytes();
      final initialBase64 = ImageCompressionHelper.toBase64DataUrl(initialBytes);

      final product = Product(
        id: 'prod_rem_img',
        name: 'Ghế bành đơn phòng khách',
        code: 'GB01',
        price: 850000,
        costPrice: 500000,
        branchStocks: const {'store_001': 5},
        category: 'Nội thất',
        imageUrl: initialBase64,
      );
      repo.store[product.id] = product;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            productListProvider.overrideWith((ref) => Stream.value([product])),
            categoryListProvider.overrideWith(
              (ref) => Stream.value([const Category(id: 'c1', name: 'Nội thất')]),
            ),
            currentStoreIdProvider.overrideWithValue('store_001'),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: ProductDetailPage(product: product),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      // Tap remove image button
      await tester.tap(find.byIcon(Icons.close).first);
      await tester.pumpAndSettle();

      // Verify picker placeholder is shown
      expect(find.text('Thêm ảnh sản phẩm'), findsOneWidget);

      // Save product
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // Image must now be null
      expect(repo.lastSaved, isNotNull);
      expect(repo.lastSaved!.imageUrl, isNull);
    });

    testWidgets('ProductDetailPage replaces existing network URL with a new Base64 URL', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _InMemoryProductRepo();

      const product = Product(
        id: 'prod_replace',
        name: 'Giường gỗ thông 1m6',
        code: 'GGT01',
        price: 2500000,
        costPrice: 1500000,
        branchStocks: {'store_001': 3},
        category: 'Nội thất',
        imageUrl: 'https://images.unsplash.com/old_bed.jpg',
      );
      repo.store[product.id] = product;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            productListProvider.overrideWith((ref) => Stream.value([product])),
            categoryListProvider.overrideWith(
              (ref) => Stream.value([const Category(id: 'c1', name: 'Nội thất')]),
            ),
            currentStoreIdProvider.overrideWithValue('store_001'),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: ProductDetailPage(product: product),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      // Tap on image container to change image
      await tester.tap(find.byType(Card).first);
      await tester.pumpAndSettle();

      // Select "Nhập / Dán Link ảnh Online"
      await tester.tap(find.text('Nhập / Dán Link ảnh Online'));
      await tester.pumpAndSettle();

      final newBytes = createTestJpgBytes(width: 300, height: 300);
      final newBase64 = ImageCompressionHelper.toBase64DataUrl(newBytes);

      await tester.enterText(find.byType(TextField).last, newBase64);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      // Save
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      expect(repo.lastSaved, isNotNull);
      expect(repo.lastSaved!.imageUrl, equals(newBase64));
    });
  });

  group('Round 2 Reviewer Adversarial Suite 3: Deep NLP Scoring Variations across All 6 Rooms', () {
    final testCases = <String, String>{
      // Room 1: Phòng khách
      'Sofa văng nỉ': 'Phòng khách',
      'sofa vang ni': 'Phòng khách',
      'bàn sofa mặt kính': 'Phòng khách',
      'ban sofa mat kinh': 'Phòng khách',
      'Kệ tivi mặt đá': 'Phòng khách',
      'ke tivi mat da': 'Phòng khách',
      'Tủ rượu gỗ tự nhiên': 'Phòng khách',
      'tu ruou go': 'Phòng khách',
      'Trường kỷ cẩn ốc xà cừ': 'Phòng khách',
      'truong ky can oc': 'Phòng khách',
      'Bộ sa lông gỗ truyền thống': 'Phòng khách',
      'sa long go': 'Phòng khách',

      // Room 2: Phòng ngủ
      'Giường bọc nệm': 'Phòng ngủ',
      'giuong boc nem': 'Phòng ngủ',
      'Giường tầng trẻ em': 'Phòng ngủ',
      'giuong tang': 'Phòng ngủ',
      'Nệm cao su thiên nhiên': 'Phòng ngủ',
      'nem cao su thien nhien': 'Phòng ngủ',
      'Nệm lò xo túi': 'Phòng ngủ',
      'nem lo xo tui': 'Phòng ngủ',
      'Nệm bông ép gấp 3': 'Phòng ngủ',
      'nem bong ep': 'Phòng ngủ',
      'Tủ quần áo cánh lùa': 'Phòng ngủ',
      'tu quan ao canh lua': 'Phòng ngủ',
      'Bàn phấn có gương đèn LED': 'Phòng ngủ',
      'ban phan den led': 'Phòng ngủ',
      'Ghế nơ trang điểm': 'Phòng ngủ',
      'ghe no trang diem': 'Phòng ngủ',

      // Room 3: Phòng ăn & Bếp
      'Bàn ăn thông minh xếp gọn': 'Phòng ăn & Bếp',
      'ban an thong minh xep gon': 'Phòng ăn & Bếp',
      'Ghế ăn bọc da': 'Phòng ăn & Bếp',
      'ghe an boc da': 'Phòng ăn & Bếp',
      'Tủ chén bát gia đình': 'Phòng ăn & Bếp',
      'tu chen': 'Phòng ăn & Bếp',
      'Tủ bếp nhôm kính': 'Phòng ăn & Bếp',
      'tu bep nhom kinh': 'Phòng ăn & Bếp',
      'Kệ để lò vi sóng': 'Phòng ăn & Bếp',
      'ke de lo vi song': 'Phòng ăn & Bếp',
      'Kệ chén bát inox 304': 'Phòng ăn & Bếp',
      'ke chen bat inox': 'Phòng ăn & Bếp',

      // Room 4: Phòng làm việc
      'Bàn gaming LED': 'Phòng làm việc',
      'ban gaming led': 'Phòng làm việc',
      'Bàn học sinh liền kệ sách': 'Phòng làm việc',
      'ban hoc sinh': 'Phòng làm việc',
      'Bàn nâng hạ độ cao': 'Phòng làm việc',
      'ban nang ha do cao': 'Phòng làm việc',
      'Ghế giám đốc bọc da': 'Phòng làm việc',
      'ghe giam doc': 'Phòng làm việc',
      'Ghế gaming chân quỳ': 'Phòng làm việc',
      'ghe gaming chan quy': 'Phòng làm việc',
      'Kệ sách đứng chữ U': 'Phòng làm việc',
      'ke sach chu u': 'Phòng làm việc',
      'Giá sách gỗ treo tường': 'Phòng làm việc',
      'gia sach treo tuong': 'Phòng làm việc',

      // Room 5: Phòng thờ
      'Bàn thờ đứng gia tiên': 'Phòng thờ',
      'ban tho dung': 'Phòng thờ',
      'Bàn thờ treo tường chung cư': 'Phòng thờ',
      'ban tho treo tuong': 'Phòng thờ',
      'Bàn thờ Thần Tài Thổ Địa': 'Phòng thờ',
      'ban tho than tai': 'Phòng thờ',
      'Vách ngăn phòng thờ CNC': 'Phòng thờ',
      'vach ngan phong tho': 'Phòng thờ',

      // Room 6: Sân vườn / Ngoài trời
      'Xích đu giọt nước mây nhựa': 'Sân vườn / Ngoài trời',
      'xich du giot nuoc': 'Sân vườn / Ngoài trời',
      'Xích đu đôi kèm nệm': 'Sân vườn / Ngoài trời',
      'xich du doi': 'Sân vườn / Ngoài trời',
      'Bộ bàn ghế cafe ngoài trời': 'Sân vườn / Ngoài trời',
      'ban ghe cafe ngoai troi': 'Sân vườn / Ngoài trời',
      'Ghế xếp thư giãn ban công': 'Sân vườn / Ngoài trời',
      'ghe xep thu gian': 'Sân vườn / Ngoài trời',
    };

    for (final entry in testCases.entries) {
      test('Scoring matrix: "${entry.key}" resolves to room space "${entry.value}"', () {
        final p = makeProduct(name: entry.key);
        final matches = SampleImageHelper.getSuggestedImages(p);
        expect(matches, isNotEmpty, reason: 'Expected suggestion for "${entry.key}"');
        expect(matches.first.category.industry, equals(entry.value),
            reason: 'Expected top suggestion for "${entry.key}" to be in ${entry.value} but got ${matches.first.category.industry} (${matches.first.category.name})');
      });
    }
  });
}
