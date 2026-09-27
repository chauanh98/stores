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
import 'package:stores/domain/entities/category.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';
import 'package:stores/presentation/products/widgets/product_tile.dart';

class _MockAuthNotifier extends StateNotifier<UserAccount?> implements AuthNotifier {
  _MockAuthNotifier()
      : super(
          const UserAccount(
            username: 'admin',
            displayName: 'Admin Tester',
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

class _TrackingProductRepo implements ProductRepository {
  final Map<String, Product> store = {};
  Product? lastSaved;
  final List<Product> saveHistory = [];

  @override
  Future<void> upsert(Product product) async {
    lastSaved = product;
    saveHistory.add(product);
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

class _MockImageUploadService extends ImageUploadService {
  int uploadCallCount = 0;
  final List<String> deletedUrls = [];
  String nextUploadUrl = 'https://firebasestorage.googleapis.com/v0/b/test/o/upload_1.jpg';
  bool nextIsBase64 = false;

  @override
  Future<ImageUploadResult> uploadProductImage({
    required String storeId,
    required String productId,
    dynamic file,
    Uint8List? bytes,
  }) async {
    uploadCallCount++;
    return ImageUploadResult(
      imageUrl: nextUploadUrl,
      isFallbackBase64: nextIsBase64,
    );
  }

  @override
  Future<void> deleteProductImage(String? imageUrl) async {
    if (imageUrl != null && imageUrl.isNotEmpty) {
      deletedUrls.add(imageUrl);
    }
  }
}

void main() {
  Uint8List createSampleImageBytes(int width, int height) {
    final image = img.Image(width: width, height: height);
    img.fill(image, color: img.ColorRgb8(50, 180, 100));
    return Uint8List.fromList(img.encodeJpg(image, quality: 80));
  }

  group('Reviewer 3 Adversarial & Deep Verification Tests', () {
    test('ImageCompressionHelper.compressImageBytes strictly respects non-square constraints (maxWidth: 600, maxHeight: 200)', () {
      // Create image 1200 x 1000
      final rawImageBytes = createSampleImageBytes(1200, 1000);

      final compressed = ImageCompressionHelper.compressImageBytes(
        rawImageBytes,
        maxWidth: 600,
        maxHeight: 200,
        quality: 75,
      );

      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(600));
      expect(decoded.height, lessThanOrEqualTo(200));
      // With width=1200, height=1000 and bound 600x200:
      // scale = min(600/1200, 200/1000) = min(0.5, 0.2) = 0.2
      // height should be 200, width should be 240
      expect(decoded.height, equals(200));
      expect(decoded.width, equals(240));
    });

    test('ImageCompressionHelper.decodeBase64DataUrl successfully handles unpadded base64 and URI-encoded data', () {
      final sampleBytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      // Encode to standard base64: "ChQeKDI="
      final standardB64 = base64Encode(sampleBytes);
      expect(standardB64.endsWith('='), isTrue);

      // Strip padding to create unpadded base64: "ChQeKDI"
      final unpaddedPayload = standardB64.replaceAll('=', '');
      final unpaddedDataUrl = 'data:image/jpeg;base64,$unpaddedPayload';

      final decoded = ImageCompressionHelper.decodeBase64DataUrl(unpaddedDataUrl);
      expect(decoded, isNotNull);
      expect(decoded, equals(sampleBytes));

      // Test percent-encoded base64 URL
      final encodedPayload = Uri.encodeComponent(standardB64);
      final encodedDataUrl = 'data:image/jpeg;base64,$encodedPayload';
      final decodedFromEncoded = ImageCompressionHelper.decodeBase64DataUrl(encodedDataUrl);
      expect(decodedFromEncoded, isNotNull);
      expect(decodedFromEncoded, equals(sampleBytes));
    });

    test('ImageUploadService.deleteProductImage skips non-Firebase third-party URLs without error', () async {
      final service = ImageUploadService();

      // External URLs must NOT be queried against FirebaseStorage.refFromURL
      await expectLater(
        service.deleteProductImage('https://images.unsplash.com/photo-123456789.jpg'),
        completes,
      );
      await expectLater(
        service.deleteProductImage('https://cdn.pixabay.com/photo/2026/test.png'),
        completes,
      );
    });

    testWidgets('ProductDetailPage: Sequential edits in the same session reset temporary inputs cleanly', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _TrackingProductRepo();
      final uploadService = _MockImageUploadService();

      const initialProduct = Product(
        id: 'prod_multi_edit',
        name: 'Trà ô long sữa nướng',
        code: 'TOLSN',
        price: 35000,
        costPrice: 18000,
        branchStocks: {'store_001': 20},
        category: 'Đồ uống',
        imageUrl: 'https://firebasestorage.googleapis.com/v0/b/test/o/initial.jpg',
      );
      repo.store[initialProduct.id] = initialProduct;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            imageUploadServiceProvider.overrideWithValue(uploadService),
            productListProvider.overrideWith((ref) => Stream.value([initialProduct])),
            currentStoreIdProvider.overrideWithValue('store_001'),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: ProductDetailPage(product: initialProduct),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // --- EDIT 1: Set Online URL ---
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Đổi ảnh'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhập / Dán Link ảnh Online'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'https://example.com/online_edit_1.jpg');
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // Verify edit 1 saved
      expect(repo.lastSaved, isNotNull);
      expect(repo.lastSaved!.imageUrl, equals('https://example.com/online_edit_1.jpg'));
      expect(uploadService.uploadCallCount, equals(0)); // Online URL does not invoke uploadProductImage

      // --- EDIT 2: In the same page session, edit price only WITHOUT touching image ---
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      final priceField = find.widgetWithText(TextFormField, 'Giá bán');
      await tester.enterText(priceField, '42000');
      await tester.pumpAndSettle();

      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // Verify edit 2 saved new price, kept the previous image, and did NOT re-trigger image upload or deletion
      expect(repo.lastSaved!.price, equals(42000));
      expect(repo.lastSaved!.imageUrl, equals('https://example.com/online_edit_1.jpg'));
      expect(uploadService.uploadCallCount, equals(0));
    });

    testWidgets('AddProductPage: Shows Base64 backup badge when editing product with Base64 imageUrl', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sampleBytes = createSampleImageBytes(200, 200);
      final b64Url = ImageCompressionHelper.toBase64DataUrl(sampleBytes);

      final base64Product = Product(
        id: 'prod_b64_edit',
        name: 'Trà đào cam sả',
        code: 'TDCS',
        price: 30000,
        costPrice: 15000,
        branchStocks: const {'store_001': 10},
        category: 'Đồ uống',
        imageUrl: b64Url,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productListProvider.overrideWith((ref) => Stream.value([base64Product])),
            categoryListProvider.overrideWith(
              (ref) => Stream.value([const Category(id: 'c1', name: 'Đồ uống')]),
            ),
            currentStoreIdProvider.overrideWithValue('store_001'),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: AddProductPage(product: base64Product),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The Base64 backup badge must be visible in AddProductPage
      expect(find.text('Ảnh dự phòng (Base64)'), findsOneWidget);
      expect(find.byIcon(Icons.shield_outlined), findsOneWidget);

      // Tapping the badge opens the Storage Activation Guide dialog
      await tester.tap(find.text('Ảnh dự phòng (Base64)'));
      await tester.pumpAndSettle();

      expect(find.text('Kích hoạt Firebase Storage'), findsOneWidget);
      expect(find.text('console.firebase.google.com'), findsOneWidget);
      expect(find.text('Đã hiểu'), findsOneWidget);

      // Dismiss dialog
      await tester.tap(find.text('Đã hiểu'));
      await tester.pumpAndSettle();
    });

    testWidgets('ProductTile & POS: Product with images list but null imageUrl renders correctly', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final sampleBytes = createSampleImageBytes(100, 100);
      final b64 = ImageCompressionHelper.toBase64DataUrl(sampleBytes);

      // Product has images array populated, but imageUrl is null
      final productWithImagesList = Product(
        id: 'prod_images_list',
        name: 'Bánh mì thịt nướng',
        code: 'BMTN',
        price: 25000,
        costPrice: 12000,
        branchStocks: const {'store_001': 5},
        category: 'Thức ăn',
        imageUrl: null,
        images: [b64],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            productListProvider.overrideWith((ref) => Stream.value([productWithImagesList])),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: Scaffold(
              body: ProductTile(
                product: productWithImagesList,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // ProductTile should resolve primaryImageUrl and render the image from images list
      expect(find.byType(Image), findsOneWidget);
    });
  });
}
