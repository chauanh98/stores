import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';

void main() {
  group('ProductImageThumbnail URL resolution tests', () {
    test('resolvePrimaryUrl handles null, empty, and invalid URLs', () {
      expect(ProductImageThumbnail.resolvePrimaryUrl(null), isNull);
      expect(ProductImageThumbnail.resolvePrimaryUrl(''), isNull);
      expect(ProductImageThumbnail.resolvePrimaryUrl('   '), isNull);
      expect(ProductImageThumbnail.resolvePrimaryUrl('not-a-url'), isNull);
    });

    test('resolvePrimaryUrl handles single URL', () {
      const url = 'https://cdn-images.kiotviet.vn/photo1.jpg';
      expect(ProductImageThumbnail.resolvePrimaryUrl(url), equals(url));
    });

    test('resolvePrimaryUrl safely extracts first URL from comma-separated list', () {
      const raw =
          'https://cdn-images.kiotviet.vn/photo1.jpg,https://cdn-images.kiotviet.vn/photo2.jpg,https://cdn-images.kiotviet.vn/photo3.jpg';
      expect(
        ProductImageThumbnail.resolvePrimaryUrl(raw),
        equals('https://cdn-images.kiotviet.vn/photo1.jpg'),
      );
    });

    test('resolvePrimaryUrl trims whitespace around URLs', () {
      const raw =
          '  https://cdn-images.kiotviet.vn/photo1.jpg  ,  https://cdn-images.kiotviet.vn/photo2.jpg ';
      expect(
        ProductImageThumbnail.resolvePrimaryUrl(raw),
        equals('https://cdn-images.kiotviet.vn/photo1.jpg'),
      );
    });

    test('resolveAllUrls parses all valid URLs', () {
      const raw =
          'https://cdn-images.kiotviet.vn/photo1.jpg, https://cdn-images.kiotviet.vn/photo2.jpg, not-valid';
      final list = ProductImageThumbnail.resolveAllUrls(raw);
      expect(list.length, equals(2));
      expect(list[0], equals('https://cdn-images.kiotviet.vn/photo1.jpg'));
      expect(list[1], equals('https://cdn-images.kiotviet.vn/photo2.jpg'));
    });
  });

  group('Product Entity Image Getters Tests', () {
    test('allImageUrls and primaryImageUrl handle comma-separated imageUrl', () {
      const product = Product(
        id: 'VP67',
        name: 'Bàn VIP',
        code: 'VP67',
        price: 1000000,
        costPrice: 500000,
        branchStocks: {'store_002': 5},
        category: 'Bàn',
        imageUrl:
            'https://cdn-images.kiotviet.vn/1.jpeg,https://cdn-images.kiotviet.vn/2.jpeg',
      );

      expect(product.allImageUrls.length, equals(2));
      expect(product.primaryImageUrl, equals('https://cdn-images.kiotviet.vn/1.jpeg'));
    });

    test('allImageUrls prioritizes images list if provided', () {
      const product = Product(
        id: 'VP67',
        name: 'Bàn VIP',
        code: 'VP67',
        price: 1000000,
        costPrice: 500000,
        branchStocks: {'store_002': 5},
        category: 'Bàn',
        imageUrl: 'https://cdn-images.kiotviet.vn/fallback.jpeg',
        images: [
          'https://cdn-images.kiotviet.vn/img1.jpeg',
          'https://cdn-images.kiotviet.vn/img2.jpeg',
        ],
      );

      expect(product.allImageUrls.length, equals(2));
      expect(product.allImageUrls[0], equals('https://cdn-images.kiotviet.vn/img1.jpeg'));
      expect(product.primaryImageUrl, equals('https://cdn-images.kiotviet.vn/img1.jpeg'));
    });
  });

  group('ProductImageThumbnail Widget Tests', () {
    testWidgets('renders placeholder when imageUrl is null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: null,
              productName: 'Tủ gỗ',
              categoryName: 'Nội thất',
            ),
          ),
        ),
      );

      expect(find.byType(ProductImageThumbnail), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('renders Image.network with single URL when comma-separated URL given',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl:
                  'https://cdn-images.kiotviet.vn/photo1.jpg,https://cdn-images.kiotviet.vn/photo2.jpg',
              productName: 'Tủ gỗ',
              categoryName: 'Nội thất',
            ),
          ),
        ),
      );

      expect(find.byType(ProductImageThumbnail), findsOneWidget);
      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final imageWidget = tester.widget<Image>(imageFinder);
      final imageProvider = imageWidget.image;
      final NetworkImage networkImage;
      if (imageProvider is ResizeImage) {
        expect(imageProvider.width, equals(150));
        expect(imageProvider.height, equals(150));
        networkImage = imageProvider.imageProvider as NetworkImage;
      } else {
        networkImage = imageProvider as NetworkImage;
      }
      expect(networkImage.url, equals('https://cdn-images.kiotviet.vn/photo1.jpg'));
    });

    testWidgets('renders Image.network with custom cacheWidth and cacheHeight',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: 'https://cdn-images.kiotviet.vn/photo1.jpg',
              productName: 'Tủ gỗ',
              categoryName: 'Nội thất',
              cacheWidth: 300,
              cacheHeight: 200,
            ),
          ),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final imageWidget = tester.widget<Image>(imageFinder);
      final imageProvider = imageWidget.image;
      expect(imageProvider, isA<ResizeImage>());
      final resizeImage = imageProvider as ResizeImage;
      expect(resizeImage.width, equals(300));
      expect(resizeImage.height, equals(200));
      final networkImage = resizeImage.imageProvider as NetworkImage;
      expect(networkImage.url, equals('https://cdn-images.kiotviet.vn/photo1.jpg'));
    });

    testWidgets('renders Image.network with unconstrained cache when null is passed',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: 'https://cdn-images.kiotviet.vn/photo1.jpg',
              productName: 'Tủ gỗ',
              categoryName: 'Nội thất',
              cacheWidth: null,
              cacheHeight: null,
            ),
          ),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);

      final imageWidget = tester.widget<Image>(imageFinder);
      final imageProvider = imageWidget.image;
      // When both cacheWidth and cacheHeight are null, Image.network does not wrap in ResizeImage
      expect(imageProvider, isA<NetworkImage>());
      final networkImage = imageProvider as NetworkImage;
      expect(networkImage.url, equals('https://cdn-images.kiotviet.vn/photo1.jpg'));
    });
  });
}
