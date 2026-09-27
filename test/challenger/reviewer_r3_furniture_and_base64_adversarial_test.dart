import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/products/services/image_upload_service.dart';
import 'package:stores/core/utils/image_compression_helper.dart';
import 'package:stores/core/utils/sample_image_helper.dart';
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
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

class _CountingImageUploadService extends ImageUploadService {
  int uploadCallCount = 0;
  int deleteCallCount = 0;

  @override
  Future<ImageUploadResult> uploadProductImage({
    required String storeId,
    required String productId,
    dynamic file,
    Uint8List? bytes,
  }) async {
    uploadCallCount++;
    return super.uploadProductImage(
      storeId: storeId,
      productId: productId,
      file: file,
      bytes: bytes,
    );
  }

  @override
  Future<void> deleteProductImage(String? imageUrl) async {
    deleteCallCount++;
    return super.deleteProductImage(imageUrl);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Uint8List createSampleJpgBytes({int width = 200, int height = 200, int quality = 75}) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(120, 80, 40));
    return Uint8List.fromList(img.encodeJpg(image, quality: quality));
  }

  Product makeProduct({
    required String name,
    String category = '',
    String? imageUrl,
  }) {
    return Product(
      id: 'prod_${name.hashCode}',
      code: 'SP001',
      name: name,
      category: category,
      price: 2500000,
      costPrice: 1500000,
      branchStocks: const {'store_001': 8},
      imageUrl: imageUrl,
    );
  }

  group('Round 3 Adversarial Suite 1: Image Compression Edge Cases & Re-compression Avoidance', () {
    test('compressImageBytes handles zero-byte input gracefully', () {
      final empty = Uint8List(0);
      final result = ImageCompressionHelper.compressImageBytes(empty);
      expect(result, isEmpty);
    });

    test('compressImageBytes handles non-image / corrupted bytes gracefully without throwing', () {
      final corrupted = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final result = ImageCompressionHelper.compressImageBytes(corrupted);
      expect(result, equals(corrupted));
    });

    test('compressImageBytes downscales large 2400x1600 landscape image to <= 300x300 and < 30KB', () {
      final largeBytes = createSampleJpgBytes(width: 2400, height: 1600, quality: 90);
      expect(largeBytes.length, greaterThan(35 * 1024));

      final compressed = ImageCompressionHelper.compressImageBytes(
        largeBytes,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      expect(compressed, isNotEmpty);
      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(300));
      expect(decoded.height, equals(200));
      expect(compressed.length, lessThanOrEqualTo(30 * 1024));
    });

    test('compressImageBytes downscales portrait 1600x2400 image to <= 300x300 and < 30KB', () {
      final largeBytes = createSampleJpgBytes(width: 1600, height: 2400, quality: 90);

      final compressed = ImageCompressionHelper.compressImageBytes(
        largeBytes,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(200));
      expect(decoded.height, equals(300));
      expect(compressed.length, lessThanOrEqualTo(30 * 1024));
    });

    test('compressImageBytes avoids re-compression when image is already lightweight JPEG within bounds', () {
      // Create a 200x150 JPEG that is already small (< 30KB)
      final existingJpeg = createSampleJpgBytes(width: 200, height: 150, quality: 70);
      expect(existingJpeg.length, lessThanOrEqualTo(30 * 1024));

      final result = ImageCompressionHelper.compressImageBytes(
        existingJpeg,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      // Must return identical bytes directly to avoid generational degradation
      expect(identical(result, existingJpeg) || result == existingJpeg, isTrue);
      expect(result.length, equals(existingJpeg.length));
    });

    test('ImageUploadService avoids re-compression when bytes are UTF-8 encoded Base64 Data URL', () async {
      final service = ImageUploadService();
      final sampleImg = createSampleJpgBytes(width: 200, height: 200);
      final validDataUrl = ImageCompressionHelper.toBase64DataUrl(sampleImg);
      final utf8Bytes = Uint8List.fromList(utf8.encode(validDataUrl));

      final uploadResult = await service.uploadProductImage(
        storeId: 'store_001',
        productId: 'prod_b64_test',
        bytes: utf8Bytes,
      );

      expect(uploadResult.imageUrl, equals(validDataUrl));
      expect(uploadResult.isFallbackBase64, isTrue);
      expect(uploadResult.byteLength, equals(sampleImg.length));
    });
  });

  group('Round 3 Adversarial Suite 2: 100% Furniture Room-Space Catalog Completeness & NLP Matching', () {
    test('Catalog contains exactly 6 Room Spaces in defined roomOrder', () {
      const expectedRooms = [
        'Phòng khách',
        'Phòng ngủ',
        'Phòng ăn & Bếp',
        'Phòng làm việc',
        'Phòng thờ',
        'Sân vườn / Ngoài trời',
      ];

      expect(SampleImageHelper.roomOrder, equals(expectedRooms));
      expect(SampleImageHelper.industries, equals(expectedRooms));

      final foundIndustries = SampleImageHelper.catalog.map((c) => c.industry).toSet();
      expect(foundIndustries, equals(expectedRooms.toSet()));
    });

    test('Catalog has strictly zero non-furniture items', () {
      for (final cat in SampleImageHelper.catalog) {
        expect(cat.industry, isIn(SampleImageHelper.roomOrder));
        expect(cat.id.startsWith('beverage_'), isFalse);
        expect(cat.id.startsWith('food_'), isFalse);
        expect(cat.id.startsWith('cosmetics_'), isFalse);
        expect(cat.id.startsWith('pharma_'), isFalse);
        expect(cat.id.startsWith('fmcg_'), isFalse);
        expect(cat.id.startsWith('baby_'), isFalse);
        expect(cat.id.startsWith('pet_'), isFalse);
      }
    });

    test('Every one of the 6 Room Spaces has all specified items from R2 requirements', () {
      final roomItems = <String, List<String>>{
        'Phòng khách': [
          'Sofa văng',
          'Sofa nỉ góc chữ L & Sofa da, Sofa bed',
          'Sofa giường thông minh',
          'Ghế bành đơn',
          'Bàn trà đôi mặt đá',
          'Bàn sofa mặt kính',
          'Bàn trà tròn gỗ',
          'Kệ Tivi mặt đá',
          'Kệ tivi gỗ rút 2 đầu',
          'Tủ rượu phòng khách',
          'Trường kỷ gỗ gụ',
          'Trường kỷ cẩn ốc xà cừ',
          'Bộ sa lông gỗ truyền thống',
        ],
        'Phòng ngủ': [
          'Giường ngủ gỗ tự nhiên (gỗ sồi, gõ đỏ) & Nệm, Ga gối',
          'Giường bọc nệm hiện đại',
          'Giường thông minh có ngăn kéo',
          'Giường tầng',
          'Nệm cao su thiên nhiên',
          'Nệm cao su non',
          'Nệm lò xo túi',
          'Nệm bông ép gấp 3',
          'Chăn ga gối đệm nỉ nhung, Cotton Tencel',
          'Tủ quần áo cánh lùa',
          'Tủ gỗ 3-4 cánh & Kệ tivi, Tủ đầu giường, Kệ sắt',
          'Tủ nhôm kính',
          'Bàn trang điểm / Bàn phấn có gương đèn LED',
          'Ghế nơ trang điểm',
          'Tủ đầu giường (Tab đầu giường) gỗ và da',
        ],
        'Phòng ăn & Bếp': [
          'Bàn ăn mặt đá cẩm thạch chống xước & Bàn trà sofa, Bàn cafe',
          'Bàn ăn gỗ tự nhiên',
          'Bàn ăn thông minh xếp gọn kéo dài',
          'Ghế ăn bọc da cao cấp',
          'Ghế ăn gỗ Monet/Nelson',
          'Tủ chén',
          'Tủ bếp nhôm kính',
          'Kệ để lò vi sóng và nồi chiên đa năng',
          'Kệ chén bát inox',
        ],
        'Phòng làm việc': [
          'Bàn làm việc chân sắt chữ K/Z/U & Gaming, Bàn học sinh',
          'Bàn gaming LED',
          'Bàn học sinh liền kệ sách',
          'Bàn nâng hạ độ cao',
          'Ghế xoay văn phòng lưới thoáng khí',
          'Ghế xoay văn phòng lưới & Ghế công thái học, Gaming, Giám đốc',
          'Ghế giám đốc bọc da',
          'Ghế gaming chân quỳ',
          'Kệ sách đứng chữ U',
          'Kệ tài liệu văn phòng',
          'Giá sách gỗ treo tường',
        ],
        'Phòng thờ': [
          'Tủ thờ gia tiên gỗ gõ đỏ/gụ',
          'Bàn thờ đứng trang nghiêm',
          'Bàn thờ treo tường chung cư',
          'Bàn thờ Thần Tài Thổ Địa',
          'Ghế cao thắp nhang (Ghế đốt nhang gỗ có tay vịn)',
          'Vách ngăn phòng thờ CNC',
        ],
        'Sân vườn / Ngoài trời': [
          'Xích đu sắt mỹ thuật sơn tĩnh điện ngoài trời',
          'Xích đu giọt nước mây nhựa',
          'Xích đu đôi kèm nệm êm',
          'Bộ bàn ghế cafe ngoài trời',
          'Ghế xếp thư giãn ban công',
        ],
      };

      for (final entry in roomItems.entries) {
        final room = entry.key;
        final expectedNames = entry.value;
        final categoriesInRoom =
            SampleImageHelper.catalog.where((c) => c.industry == room).map((c) => c.name).toSet();

        for (final expected in expectedNames) {
          expect(categoriesInRoom.contains(expected), isTrue,
              reason: 'Expected category "$expected" to exist in room "$room"');
        }
      }
    });

    test('furnitureOnly flag blocks non-furniture fallback in getSuggestedImages & getSampleImageUrl', () {
      final beerProduct = makeProduct(name: 'Bia Heineken lon 330ml', category: 'Đồ uống');

      // Without furnitureOnly, legacy catalog could match
      final legacyMatches = SampleImageHelper.getSuggestedImages(beerProduct, furnitureOnly: false);
      expect(legacyMatches, isNotEmpty);

      // With furnitureOnly: true, strictly ZERO matches
      final furnitureOnlyMatches = SampleImageHelper.getSuggestedImages(beerProduct, furnitureOnly: true);
      expect(furnitureOnlyMatches, isEmpty);

      // getSampleImageUrl with furnitureOnly: true returns empty string
      final sampleUrl = SampleImageHelper.getSampleImageUrl(beerProduct, furnitureOnly: true);
      expect(sampleUrl, isEmpty);
    });

    test('NLP scoring handles abbreviations and variations across all 6 rooms', () {
      final testCases = <String, String>{
        // Room 1
        'Sofa L': 'Phòng khách',
        'sofa l': 'Phòng khách',
        'kệ tv': 'Phòng khách',
        'ke tv': 'Phòng khách',
        'trường kỷ': 'Phòng khách',
        'truong ky': 'Phòng khách',
        // Room 2
        'giường 1m8': 'Phòng ngủ',
        'giuong 1m8': 'Phòng ngủ',
        'nệm cao su non': 'Phòng ngủ',
        'nem cao su non': 'Phòng ngủ',
        // Room 3
        'bàn ăn': 'Phòng ăn & Bếp',
        'ban an': 'Phòng ăn & Bếp',
        'kệ lò vi sóng': 'Phòng ăn & Bếp',
        'ke lo vi song': 'Phòng ăn & Bếp',
        // Room 4
        'bàn gaming': 'Phòng làm việc',
        'ban gaming': 'Phòng làm việc',
        'ghế ergonomic': 'Phòng làm việc',
        'ghe ergonomic': 'Phòng làm việc',
        // Room 5
        'ghế đốt nhang': 'Phòng thờ',
        'ghe dot nhang': 'Phòng thờ',
        'tủ thờ': 'Phòng thờ',
        'tu tho': 'Phòng thờ',
        // Room 6
        'xích đu sắt': 'Sân vườn / Ngoài trời',
        'xich du sat': 'Sân vườn / Ngoài trời',
        'ghế thư giãn ban công': 'Sân vườn / Ngoài trời',
        'ghe thu gian ban cong': 'Sân vườn / Ngoài trời',
      };

      for (final entry in testCases.entries) {
        final p = makeProduct(name: entry.key);
        final matches = SampleImageHelper.getSuggestedImages(p, furnitureOnly: true);
        expect(matches, isNotEmpty, reason: 'Expected match for query "${entry.key}"');
        expect(matches.first.category.industry, equals(entry.value),
            reason: 'Query "${entry.key}" expected in room "${entry.value}" but got "${matches.first.category.industry}"');
      }
    });
  });

  group('Round 3 Adversarial Suite 3: UI Responsiveness, Dialog Dismissal & Search Polish', () {
    testWidgets('SampleImagePickerDialog dismisses via Close button and returns null', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? selectedResult = 'initial_val';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedResult = await SampleImagePickerDialog.show(
                    context,
                    productName: 'Bàn trà sofa gỗ',
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

      expect(find.text('Gợi ý & Chọn Ảnh Mẫu Thông Minh'), findsOneWidget);

      // Tap close icon
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // Dialog dismissed, result is null
      expect(find.text('Gợi ý & Chọn Ảnh Mẫu Thông Minh'), findsNothing);
      expect(selectedResult, isNull);
    });

    testWidgets('SampleImagePickerDialog image tap selects image URL immediately', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? selectedResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () async {
                  selectedResult = await SampleImagePickerDialog.show(
                    context,
                    productName: 'Sofa góc L',
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

      // Find suggested card
      final card = find.text('Sofa nỉ góc chữ L & Sofa da, Sofa bed');
      expect(card, findsWidgets);

      await tester.tap(card.first);
      await tester.pumpAndSettle();

      expect(selectedResult, isNotNull);
      expect(selectedResult, startsWith('https://images.unsplash.com/'));
    });

    testWidgets('Quick search and room chip filtering work seamlessly together', (tester) async {
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

      final searchField = find.byType(TextField).first;

      // 1. Search "xích đu"
      await tester.enterText(searchField, 'xích đu');
      await tester.pumpAndSettle();

      expect(find.text('Xích đu sắt mỹ thuật sơn tĩnh điện ngoài trời'), findsOneWidget);
      expect(find.text('Xích đu giọt nước mây nhựa'), findsOneWidget);

      // 2. Select "Phòng khách" chip while search is active -> should find 0
      await tester.tap(find.widgetWithText(ChoiceChip, 'Phòng khách'));
      await tester.pumpAndSettle();

      expect(find.text('Không tìm thấy ảnh mẫu phù hợp'), findsOneWidget);

      // 3. Clear search query
      await tester.tap(find.byIcon(Icons.clear));
      await tester.pumpAndSettle();

      // Living room items show up
      expect(find.text('Sofa văng'), findsOneWidget);
      expect(find.text('Bộ sa lông gỗ truyền thống'), findsOneWidget);
    });
  });

  group('Round 3 Adversarial Suite 4: AddProductPage & ProductDetailPage Base64 Lifecycle & Redundant Compression Avoidance', () {
    testWidgets('AddProductPage saves Base64 image directly without triggering ImageUploadService re-compression', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      final repo = _InMemoryProductRepo();
      final uploadService = _CountingImageUploadService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            imageUploadServiceProvider.overrideWithValue(uploadService),
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

      await tester.enterText(find.widgetWithText(TextFormField, 'Tên hàng *'), 'Bàn ăn thông minh');
      await tester.enterText(find.widgetWithText(TextFormField, 'Giá bán'), '3500000');

      await tester.tap(find.widgetWithText(InputDecorator, 'Chọn nhóm hàng *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nội thất').first);
      await tester.pumpAndSettle();

      // Paste a valid Base64 Data URL
      await tester.tap(find.text('Thêm ảnh sản phẩm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhập / Dán Link ảnh Online'));
      await tester.pumpAndSettle();

      final dummyBytes = createSampleJpgBytes(width: 200, height: 200);
      final dummyDataUrl = ImageCompressionHelper.toBase64DataUrl(dummyBytes);
      await tester.enterText(find.byType(TextField).last, dummyDataUrl);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      // Verify the Base64 badge appears
      expect(find.text('Ảnh dự phòng (Base64)'), findsOneWidget);

      // Save product
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      // Verify saved product
      expect(repo.lastSaved, isNotNull);
      expect(repo.lastSaved!.imageUrl, equals(dummyDataUrl));
      // Re-compression upload call count must be 0 because the URL was already a direct Base64 Data URL
      expect(uploadService.uploadCallCount, equals(0));
    });

    testWidgets('ProductImageThumbnail handles corrupted Base64 without crashing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: 'data:image/jpeg;base64,CORRUPTED_NOT_VALID_BASE64_BYTES!!!',
              size: 64,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Renders placeholder without crashing
      expect(find.byType(ProductImageThumbnail), findsOneWidget);
    });

    testWidgets('ProductImageThumbnail parses and renders first URL when mixed with network URLs', (tester) async {
      final sampleJpg = createSampleJpgBytes(width: 100, height: 100);
      final b64 = ImageCompressionHelper.toBase64DataUrl(sampleJpg);
      final mixed = '$b64, https://example.com/other.jpg';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: mixed,
              size: 64,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(ProductImageThumbnail.resolvePrimaryUrl(mixed), equals(b64));
      expect(find.byType(ProductImageThumbnail), findsOneWidget);
    });
  });
}
