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
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';
import 'package:stores/presentation/products/pages/add_product_page.dart';
import 'package:stores/presentation/products/pages/product_detail_page.dart';

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

class _TrackingProductRepo implements ProductRepository {
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

class _TrackingImageUploadService extends ImageUploadService {
  bool shouldThrow = false;
  bool shouldReturnEmpty = false;
  final List<String> deletedUrls = [];
  final List<String> uploadedProductIds = [];

  @override
  Future<ImageUploadResult> uploadProductImage({
    required String storeId,
    required String productId,
    dynamic file,
    Uint8List? bytes,
  }) async {
    uploadedProductIds.add(productId);
    if (shouldThrow) {
      throw Exception('Simulated fatal platform error during image upload');
    }
    if (shouldReturnEmpty) {
      return const ImageUploadResult(
        imageUrl: '',
        isFallbackBase64: false,
        errorMessage: 'Simulated upload failure',
      );
    }
    return const ImageUploadResult(
      imageUrl: 'https://firebasestorage.googleapis.com/v0/b/test/o/new_uploaded.jpg',
      isFallbackBase64: false,
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
  Uint8List createTestImageBytes() {
    final image = img.Image(width: 400, height: 300);
    img.fill(image, color: img.ColorRgb8(10, 150, 220));
    return Uint8List.fromList(img.encodeJpg(image, quality: 80));
  }

  group('Reviewer 2 Adversarial Image System Tests', () {
    testWidgets('AddProductPage: Clicking (X) clear button when editing removes image and deletes old storage image', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _TrackingProductRepo();
      final uploadService = _TrackingImageUploadService();

      const existingProduct = Product(
        id: 'prod_edit_remove_img',
        name: 'Trà sữa trân châu hoàng gia',
        code: 'TSTC',
        price: 45000,
        costPrice: 20000,
        branchStocks: {'store_001': 30},
        category: 'Đồ uống',
        imageUrl: 'https://firebasestorage.googleapis.com/v0/b/test/o/old_image.jpg',
      );
      repo.store[existingProduct.id] = existingProduct;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            imageUploadServiceProvider.overrideWithValue(uploadService),
            productListProvider.overrideWith((ref) => Stream.value([existingProduct])),
            categoryListProvider.overrideWith(
              (ref) => Stream.value([const Category(id: 'c1', name: 'Đồ uống')]),
            ),
            currentStoreIdProvider.overrideWithValue('store_001'),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: AddProductPage(product: existingProduct),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap (X) clear button to remove the existing image
      final closeIcon = find.byIcon(Icons.close);
      expect(closeIcon, findsWidgets);
      // Close button inside the image card is inside a CircleAvatar
      final clearImageButton = find.descendant(
        of: find.byType(CircleAvatar),
        matching: find.byIcon(Icons.close),
      );
      expect(clearImageButton, findsOneWidget);

      await tester.tap(clearImageButton);
      await tester.pumpAndSettle();

      // Save the product
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      // Product must be saved with imageUrl == null (NOT reverted back to existingProduct.imageUrl)
      expect(repo.lastSaved, isNotNull);
      expect(repo.lastSaved!.imageUrl, isNull);
      // The previous storage image must have been deleted
      expect(uploadService.deletedUrls, contains(existingProduct.imageUrl));
    });

    testWidgets('ProductDetailPage: When new upload fails, existing image is preserved and not deleted', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _TrackingProductRepo();
      final uploadService = _TrackingImageUploadService();
      uploadService.shouldReturnEmpty = true; // Simulate upload failure

      const originalUrl = 'https://firebasestorage.googleapis.com/v0/b/test/o/preserve_me.jpg';
      const existingProduct = Product(
        id: 'prod_preserve_on_fail',
        name: 'Cà phê muối sữa',
        code: 'CPMS',
        price: 29000,
        costPrice: 14000,
        branchStocks: {'store_001': 25},
        category: 'Đồ uống',
        imageUrl: originalUrl,
      );
      repo.store[existingProduct.id] = existingProduct;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            imageUploadServiceProvider.overrideWithValue(uploadService),
            productListProvider.overrideWith((ref) => Stream.value([existingProduct])),
            currentStoreIdProvider.overrideWithValue('store_001'),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: ProductDetailPage(product: existingProduct),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      // Open URL dialog to replace image with empty/failed upload
      await tester.tap(find.text('Cà phê muối sữa').first);
      await tester.pumpAndSettle();

      // Save changes
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // The original image must NOT be deleted from storage
      expect(uploadService.deletedUrls, isNot(contains(originalUrl)));
      // The product entity must still retain its original image URL
      expect(repo.lastSaved!.imageUrl, equals(originalUrl));
    });

    testWidgets('ProductDetailPage: Image upload exception never aborts saving product metadata', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _TrackingProductRepo();
      final uploadService = _TrackingImageUploadService();
      uploadService.shouldThrow = true; // Simulate unexpected thrown error

      const existingProduct = Product(
        id: 'prod_save_despite_img_error',
        name: 'Nước ép bưởi hồng',
        code: 'NEBH',
        price: 40000,
        costPrice: 22000,
        branchStocks: {'store_001': 15},
        category: 'Đồ uống',
      );
      repo.store[existingProduct.id] = existingProduct;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            imageUploadServiceProvider.overrideWithValue(uploadService),
            productListProvider.overrideWith((ref) => Stream.value([existingProduct])),
            currentStoreIdProvider.overrideWithValue('store_001'),
          ],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: Locale('vi'),
            home: ProductDetailPage(product: existingProduct),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Enter edit mode
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      // Select an online URL to trigger upload logic
      await tester.tap(find.text('Thêm ảnh sản phẩm'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Nhập / Dán Link ảnh Online'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, 'https://example.com/new_photo.jpg');
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      // Update selling price
      final priceField = find.widgetWithText(TextFormField, 'Giá bán');
      await tester.enterText(priceField, '45000');
      await tester.pumpAndSettle();

      // Save changes
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // Product must be successfully saved with the updated price despite image error
      expect(repo.lastSaved, isNotNull);
      expect(repo.lastSaved!.price, equals(45000));
    });

    test('ImageUploadService: Corrupted non-image bytes reject fake Base64 generation', () async {
      final service = ImageUploadService();
      // Provide random binary bytes that cannot be decoded as an image
      final corruptedBytes = Uint8List.fromList([0, 1, 2, 3, 4, 5, 255, 254]);

      final result = await service.uploadProductImage(
        storeId: 'store_001',
        productId: 'prod_corrupt_test',
        bytes: corruptedBytes,
      );

      // Must NOT produce a Base64 data URL with raw uncompressed garbage bytes
      expect(result.imageUrl, isEmpty);
      expect(result.isFallbackBase64, isFalse);
      expect(result.errorMessage, isNotNull);
    });

    testWidgets('ProductImageThumbnail: Unsupported scheme gs:// gracefully renders category placeholder', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: 'gs://khanh-dang-store.appspot.com/products/xd15.jpg',
              productName: 'Xe Đạp Thể Thao',
              categoryName: 'Xe cộ',
              size: 50,
            ),
          ),
        ),
      );
      await tester.pump();

      // Should render placeholder icon without throwing Unsupported scheme exception
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets('AddProductPage: Previews primary image cleanly when given multi-image URLs', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _TrackingProductRepo();
      final testBytes = createTestImageBytes();
      final b64 = ImageCompressionHelper.toBase64DataUrl(testBytes);
      final multiUrl = '$b64, https://example.com/photo2.jpg';

      final multiProduct = Product(
        id: 'prod_multi',
        name: 'Trà xanh lài kem cheese',
        code: 'TXLKC',
        price: 32000,
        costPrice: 16000,
        branchStocks: const {'store_001': 10},
        category: 'Đồ uống',
        imageUrl: multiUrl,
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            productListProvider.overrideWith((ref) => Stream.value([multiProduct])),
            currentStoreIdProvider.overrideWithValue('store_001'),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            home: AddProductPage(product: multiProduct),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // It must successfully render the Base64 image from the first URL without "Link ảnh không hợp lệ"
      expect(find.text('Link ảnh không hợp lệ'), findsNothing);
      expect(find.byType(Image), findsWidgets);
    });
  });
}
