import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stores/core/utils/image_compression_helper.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';

void main() {
  group('ProductImageThumbnail URL Resolution Tests', () {
    test('resolvePrimaryUrl returns valid network URL', () {
      expect(
        ProductImageThumbnail.resolvePrimaryUrl('https://example.com/item.png'),
        equals('https://example.com/item.png'),
      );
      expect(
        ProductImageThumbnail.resolvePrimaryUrl(
            'http://example.com/item.jpg, https://example.com/other.jpg'),
        equals('http://example.com/item.jpg'),
      );
    });

    test('resolvePrimaryUrl returns Base64 Data URI intact', () {
      const base64Url =
          'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=';
      expect(
        ProductImageThumbnail.resolvePrimaryUrl(base64Url),
        equals(base64Url),
      );
    });

    test('resolvePrimaryUrl returns null for invalid or empty inputs', () {
      expect(ProductImageThumbnail.resolvePrimaryUrl(null), isNull);
      expect(ProductImageThumbnail.resolvePrimaryUrl(''), isNull);
      expect(ProductImageThumbnail.resolvePrimaryUrl('   '), isNull);
      expect(
          ProductImageThumbnail.resolvePrimaryUrl('ftp://invalid.com'), isNull);
    });

    test('resolveAllUrls correctly parses multiple URLs including Base64', () {
      const base64Url = 'data:image/jpeg;base64,ABCDEF==';
      expect(
        ProductImageThumbnail.resolveAllUrls(base64Url),
        equals([base64Url]),
      );

      expect(
        ProductImageThumbnail.resolveAllUrls(
            'https://a.com/1.jpg, https://b.com/2.jpg'),
        equals(['https://a.com/1.jpg', 'https://b.com/2.jpg']),
      );
    });
  });

  group('ProductImageThumbnail Widget Rendering Tests', () {
    Uint8List createTestImageBytes() {
      final image = img.Image(width: 50, height: 50);
      img.fill(image, color: img.ColorRgb8(200, 50, 50));
      return Uint8List.fromList(img.encodeJpg(image));
    }

    testWidgets('Renders Image.memory when given a valid Base64 Data URL',
        (tester) async {
      final testBytes = createTestImageBytes();
      final dataUrl = ImageCompressionHelper.toBase64DataUrl(testBytes);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: dataUrl,
              productName: 'Cà phê đen',
              categoryName: 'Đồ uống',
              size: 60,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Phải có widget Image được render
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('Renders category placeholder when imageUrl is null or empty',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: null,
              productName: 'Bàn ghế học sinh',
              categoryName: 'Nội thất',
              size: 48,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Khi không có ảnh, render Icon placeholder đại diện danh mục
      expect(find.byType(Icon), findsOneWidget);
      expect(find.byType(Image), findsNothing);
    });

    testWidgets(
        'Gracefully renders category placeholder when Base64 Data URL has invalid content',
        (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: 'data:image/jpeg;base64,INVALID_CONTENT_NOT_IMAGE',
              productName: 'Áo thun polo',
              categoryName: 'Thời trang',
              size: 48,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Không bị crash hoặc red screen, hiển thị placeholder
      expect(find.byType(Icon), findsOneWidget);
    });

    testWidgets(
        'Gracefully falls back to placeholder when Base64 payload is valid base64 but corrupt image format',
        (tester) async {
      // Base64 của chuỗi văn bản thuần "NOT AN IMAGE TEXT PAYLOAD", không phải JPEG/PNG
      final nonImageBase64 =
          base64Encode(utf8.encode('NOT AN IMAGE TEXT PAYLOAD 1234567890'));
      final corruptDataUrl = 'data:image/jpeg;base64,$nonImageBase64';

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: corruptDataUrl,
              productName: 'Sản phẩm lỗi ảnh',
              categoryName: 'Thực phẩm',
              size: 48,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Phải bắt lỗi qua errorBuilder và render Icon placeholder, không sập UI
      expect(find.byType(Icon), findsOneWidget);
    });

    test(
        'resolveAllUrls correctly preserves both network URL and Base64 Data URL with comma',
        () {
      const b64 = 'data:image/jpeg;base64,QUJDRA==';
      const raw =
          'https://example.com/item1.jpg, $b64, https://example.com/item2.jpg';

      final urls = ProductImageThumbnail.resolveAllUrls(raw);
      expect(urls.length, equals(3));
      expect(urls[0], equals('https://example.com/item1.jpg'));
      expect(urls[1], equals(b64));
      expect(urls[2], equals('https://example.com/item2.jpg'));
    });
  });
}
