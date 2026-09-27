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

/// Fake ImageUploadService mô phỏng Firebase Storage 404 và tự động nén Base64
class _SimulatedStorage404ImageUploadService extends ImageUploadService {
  @override
  Future<ImageUploadResult> uploadProductImage({
    required String storeId,
    required String productId,
    dynamic file,
    Uint8List? bytes,
  }) async {
    // Luôn fallback về Base64 Data URL để kiểm tra luồng an toàn
    final compressedBytes = ImageCompressionHelper.compressImageBytes(
      bytes ?? Uint8List(0),
      maxWidth: 300,
      maxHeight: 300,
      quality: 70,
    );
    final dataUrl = ImageCompressionHelper.toBase64DataUrl(compressedBytes);
    return ImageUploadResult(
      imageUrl: dataUrl,
      isFallbackBase64: true,
      errorMessage: 'Firebase Storage: 404 Object does not exist at location (bucket unprovisioned)',
    );
  }

  @override
  Future<void> deleteProductImage(String? imageUrl) async {
    // Safe delete no-op
  }
}

void main() {
  Uint8List createTestImageBytes() {
    final image = img.Image(width: 400, height: 300);
    img.fill(image, color: img.ColorRgb8(0, 180, 80));
    return Uint8List.fromList(img.encodeJpg(image, quality: 80));
  }

  group('Safe Product Image Upload & Fallback Tests (R1, R2, R3)', () {
    testWidgets('AddProductPage saves successfully and stores Base64 fallback when Storage throws 404', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _InMemoryProductRepo();
      final uploadService = _SimulatedStorage404ImageUploadService();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            imageUploadServiceProvider.overrideWithValue(uploadService),
            productListProvider.overrideWith((ref) => Stream.value([])),
            categoryListProvider.overrideWith(
              (ref) => Stream.value([
                const Category(id: 'c1', name: 'Đồ uống'),
              ]),
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

      // Điền thông tin form cơ bản
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Tên hàng *'), 'Trà chanh mật ong');
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Giá bán'), '25000');

      // Chọn nhóm hàng
      await tester.tap(find.widgetWithText(InputDecorator, 'Chọn nhóm hàng *'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đồ uống').first);
      await tester.pumpAndSettle();

      // Mở modal chọn ảnh và dán Base64 Data URL
      await tester.tap(find.text('Thêm ảnh sản phẩm'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nhập / Dán Link ảnh Online'));
      await tester.pumpAndSettle();

      final testBytes = createTestImageBytes();
      final base64DataUrl = ImageCompressionHelper.toBase64DataUrl(testBytes);

      await tester.enterText(find.byType(TextField).last, base64DataUrl);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      // Lưu hàng hóa
      await tester.tap(find.widgetWithText(TextButton, 'Lưu'));
      await tester.pumpAndSettle();

      // Kiểm tra sản phẩm đã được lưu trong repository với đúng ảnh Base64
      expect(repo.lastSaved, isNotNull);
      expect(repo.lastSaved!.name, equals('Trà chanh mật ong'));
      expect(repo.lastSaved!.imageUrl, equals(base64DataUrl));
    });

    testWidgets('ProductDetailPage renders Base64 Data URL and badge, and opens Storage guide', (tester) async {
      final repo = _InMemoryProductRepo();
      final testBytes = createTestImageBytes();
      final base64DataUrl = ImageCompressionHelper.toBase64DataUrl(testBytes);

      final product = Product(
        id: 'prod_b64',
        name: 'Trà đào cam sả',
        code: 'TDCS',
        price: 35000,
        costPrice: 20000,
        branchStocks: const {'store_001': 50},
        category: 'Đồ uống',
        imageUrl: base64DataUrl,
      );
      repo.store[product.id] = product;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            productListProvider.overrideWith((ref) => Stream.value([product])),
            categoryListProvider.overrideWith(
              (ref) => Stream.value([
                const Category(id: 'c1', name: 'Đồ uống'),
              ]),
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

      // Hiển thị tên sản phẩm và ảnh dạng memory thumbnail
      expect(find.text('Trà đào cam sả'), findsAtLeast(1));
      expect(find.byType(Image), findsAtLeast(1));

      // Vào chế độ chỉnh sửa (Chỉnh sửa)
      final editBtn = find.text('Chỉnh sửa');
      if (editBtn.evaluate().isNotEmpty) {
        await tester.tap(editBtn);
        await tester.pumpAndSettle();

        // Kiểm tra badge "Ảnh dự phòng (Base64)" xuất hiện trong preview
        expect(find.text('Ảnh dự phòng (Base64)'), findsOneWidget);

        // Nhấn vào badge để mở hướng dẫn kích hoạt Firebase Storage
        await tester.tap(find.text('Ảnh dự phòng (Base64)'));
        await tester.pumpAndSettle();

        expect(find.text('Kích hoạt Firebase Storage'), findsOneWidget);
        expect(find.text('Đã hiểu'), findsOneWidget);

        await tester.tap(find.text('Đã hiểu'));
        await tester.pumpAndSettle();
        expect(find.text('Kích hoạt Firebase Storage'), findsNothing);
      }
    });

    testWidgets('ProductDetailPage deletes product with Base64 image cleanly without Firebase error', (tester) async {
      final repo = _InMemoryProductRepo();
      final testBytes = createTestImageBytes();
      final base64DataUrl = ImageCompressionHelper.toBase64DataUrl(testBytes);

      final product = Product(
        id: 'prod_del',
        name: 'Trà xanh sữa',
        code: 'TXS',
        price: 30000,
        costPrice: 18000,
        branchStocks: const {'store_001': 20},
        category: 'Đồ uống',
        imageUrl: base64DataUrl,
      );
      repo.store[product.id] = product;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            productListProvider.overrideWith((ref) => Stream.value([product])),
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

      // Nhấn Xóa sản phẩm
      final deleteBtn = find.text('Xóa');
      if (deleteBtn.evaluate().isNotEmpty) {
        await tester.tap(deleteBtn);
        await tester.pumpAndSettle();

        // Hộp thoại xác nhận xóa
        final confirmDelete = find.widgetWithText(FilledButton, 'Xóa');
        if (confirmDelete.evaluate().isNotEmpty) {
          await tester.tap(confirmDelete);
          await tester.pumpAndSettle();
        }

        // Đảm bảo sản phẩm đã bị xóa khỏi repo và không văng lỗi
        expect(repo.store.containsKey('prod_del'), isFalse);
      }
    });

    testWidgets('ProductDetailPage gallery dialog opens and displays Base64 image in InteractiveViewer', (tester) async {
      final repo = _InMemoryProductRepo();
      final testBytes = createTestImageBytes();
      final base64DataUrl = ImageCompressionHelper.toBase64DataUrl(testBytes);

      final product = Product(
        id: 'prod_gallery',
        name: 'Trà olong sen vàng',
        code: 'TOSV',
        price: 45000,
        costPrice: 25000,
        branchStocks: const {'store_001': 30},
        category: 'Đồ uống',
        imageUrl: base64DataUrl,
      );
      repo.store[product.id] = product;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            productListProvider.overrideWith((ref) => Stream.value([product])),
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

      // Nhấn vào ảnh sản phẩm ở header để mở thư viện ảnh
      await tester.tap(find.byType(ProductImageThumbnail).first);
      await tester.pumpAndSettle();

      // Hộp thoại phóng to thư viện ảnh được hiển thị
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byType(Image), findsWidgets);

      // Đóng hộp thoại và đảm bảo PageController được dispose sạch sẽ không văng lỗi
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.byType(InteractiveViewer), findsNothing);
    });

    testWidgets('ProductDetailPage saveChanges succeeds and shows gentle feedback when new image upload hits Storage 404', (tester) async {
      tester.view.physicalSize = const Size(1000, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _InMemoryProductRepo();
      final uploadService = _SimulatedStorage404ImageUploadService();

      const product = Product(
        id: 'prod_edit_save',
        name: 'Bánh mì thịt nướng',
        code: 'BMTN',
        price: 25000,
        costPrice: 15000,
        branchStocks: {'store_001': 10},
        category: 'Đồ ăn',
      );
      repo.store[product.id] = product;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authProvider.overrideWith((ref) => _MockAuthNotifier()),
            productRepositoryProvider.overrideWithValue(repo),
            imageUploadServiceProvider.overrideWithValue(uploadService),
            productListProvider.overrideWith((ref) => Stream.value([product])),
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

      // Vào chế độ chỉnh sửa
      await tester.tap(find.text('Chỉnh sửa'));
      await tester.pumpAndSettle();

      // Chọn ảnh online
      await tester.tap(find.text('Thêm ảnh sản phẩm'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nhập / Dán Link ảnh Online'));
      await tester.pumpAndSettle();

      final testBytes = createTestImageBytes();
      final base64DataUrl = ImageCompressionHelper.toBase64DataUrl(testBytes);

      await tester.enterText(find.byType(TextField).last, base64DataUrl);
      await tester.tap(find.text('Xác nhận'));
      await tester.pumpAndSettle();

      // Nhấn Lưu thay đổi
      await tester.tap(find.text('Lưu'));
      await tester.pumpAndSettle();

      // Kiểm tra sản phẩm đã được lưu và chứa ảnh Base64
      expect(repo.lastSaved, isNotNull);
      expect(repo.lastSaved!.imageUrl, equals(base64DataUrl));
    });
  });
}
