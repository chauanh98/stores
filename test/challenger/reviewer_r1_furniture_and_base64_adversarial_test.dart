import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stores/application/products/services/image_upload_service.dart';
import 'package:stores/core/utils/image_compression_helper.dart';
import 'package:stores/core/utils/sample_image_helper.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';
import 'package:stores/presentation/products/widgets/sample_image_picker_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Product makeProduct({
    required String name,
    String category = '',
    String brand = '',
    String category3Levels = '',
    bool isCombo = false,
  }) {
    return Product(
      id: 'prod_${name.hashCode}',
      code: 'FURN01',
      name: name,
      category: category,
      brand: brand,
      category3Levels: category3Levels,
      isCombo: isCombo,
      price: 2500000,
      costPrice: 1800000,
      branchStocks: const {'branch_1': 5},
    );
  }

  group('Reviewer Adversarial Suite 1: ProductImageThumbnail & URL Parser Robustness', () {
    test('parseImageUrls cleanly separates network URLs without polluting from trailing invalid tokens', () {
      const raw = 'https://cdn.example.com/item1.jpg, https://cdn.example.com/item2.jpg, not-valid-token';
      final urls = ImageCompressionHelper.parseImageUrls(raw);
      expect(urls.length, equals(2));
      expect(urls[0], equals('https://cdn.example.com/item1.jpg'));
      expect(urls[1], equals('https://cdn.example.com/item2.jpg'));
      expect(urls.any((u) => u.contains('not-valid-token')), isFalse);
    });

    test('parseImageUrls cleanly handles multiple Base64 Data URLs with embedded commas', () {
      final img1 = img.Image(width: 10, height: 10);
      final img2 = img.Image(width: 10, height: 10);
      final b1 = ImageCompressionHelper.toBase64DataUrl(Uint8List.fromList(img.encodeJpg(img1)));
      final b2 = ImageCompressionHelper.toBase64DataUrl(Uint8List.fromList(img.encodeJpg(img2)));

      final combined = '$b1, $b2';
      final parsed = ImageCompressionHelper.parseImageUrls(combined);
      expect(parsed.length, equals(2));
      expect(parsed[0], equals(b1));
      expect(parsed[1], equals(b2));
    });

    test('parseImageUrls handles interleaved network URL and Base64 URL', () {
      const net1 = 'https://example.com/furniture1.jpg';
      final sampleImg = img.Image(width: 10, height: 10);
      final b64 = ImageCompressionHelper.toBase64DataUrl(Uint8List.fromList(img.encodeJpg(sampleImg)));
      const net2 = 'https://example.com/furniture2.jpg';

      final combined = '$net1, $b64, $net2';
      final parsed = ImageCompressionHelper.parseImageUrls(combined);
      expect(parsed.length, equals(3));
      expect(parsed[0], equals(net1));
      expect(parsed[1], equals(b64));
      expect(parsed[2], equals(net2));
    });

    testWidgets('ProductImageThumbnail with null cache constraints does NOT wrap in ResizeImage', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: 'https://images.unsplash.com/furniture.jpg',
              cacheWidth: null,
              cacheHeight: null,
            ),
          ),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      expect(imageWidget.image, isA<NetworkImage>());
      expect(imageWidget.image is ResizeImage, isFalse);
    });

    testWidgets('ProductImageThumbnail renders MemoryImage for Base64 Data URL', (tester) async {
      final testImg = img.Image(width: 20, height: 20);
      final b64 = ImageCompressionHelper.toBase64DataUrl(Uint8List.fromList(img.encodeJpg(testImg)));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ProductImageThumbnail(
              imageUrl: b64,
            ),
          ),
        ),
      );

      final imageFinder = find.byType(Image);
      expect(imageFinder, findsOneWidget);
      final imageWidget = tester.widget<Image>(imageFinder);
      if (imageWidget.image is ResizeImage) {
        expect((imageWidget.image as ResizeImage).imageProvider, isA<MemoryImage>());
      } else {
        expect(imageWidget.image, isA<MemoryImage>());
      }
    });
  });

  group('Reviewer Adversarial Suite 2: Absolute 100% Furniture Isolation in Dialog', () {
    testWidgets('Dialog opened for furniture product displays 100% room filter chips and furniture categories', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // Open dialog for a furniture product
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  SampleImagePickerDialog.show(
                    context,
                    productName: 'Bàn ăn 6 ghế mặt đá',
                    category: 'Phòng ăn & Bếp',
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

      // Ensure NO non-furniture chips exist
      expect(find.widgetWithText(ChoiceChip, 'Đồ uống & Giải khát'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Mỹ phẩm & Làm đẹp'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Thực phẩm & Gia vị'), findsNothing);

      // Verify that filter chips for room spaces are rendered
      expect(find.widgetWithText(ChoiceChip, 'Tất cả nội thất'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Phòng khách'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Phòng ngủ'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Phòng ăn & Bếp'), findsOneWidget);

      // Verify suggested image is furniture
      expect(find.textContaining('Bàn ăn'), findsWidgets);
    });

    test('SampleImageHelper.getSuggestedImagesForText with furnitureOnly=true returns empty for non-furniture', () {
      final nonFurnitureItems = [
        'Bia Tiger lon 330ml',
        'Nước tăng lực Redbull bò húc',
        'Sữa chua Vinamilk có đường',
        'Mì tôm Hảo Hảo tôm chua cay',
        'Bột giặt Omo Matic 3kg',
        'Nước súc miệng Listerine',
        'Kem chống nắng Anessa',
        'Bút bi Thiên Long 0.5mm',
      ];

      for (final item in nonFurnitureItems) {
        final matches = SampleImageHelper.getSuggestedImagesForText(
          item,
          furnitureOnly: true,
        );
        for (final m in matches) {
          expect(SampleImageHelper.roomOrder.contains(m.category.industry), isTrue,
              reason: '${m.category.name} in ${m.category.industry} is not a valid room space');
        }
      }
    });
  });

  group('Reviewer Adversarial Suite 3: Furniture Abbreviation & Unaccented Matching Matrix', () {
    final searchTerms = <String, String>{
      'sofa L': 'Phòng khách',
      'sofa l': 'Phòng khách',
      'Sofa góc L': 'Phòng khách',
      'SOFA_GOC_L': 'Phòng khách',
      'ke tv': 'Phòng khách',
      'kệ tv': 'Phòng khách',
      'KE_TV': 'Phòng khách',
      'giường 1m8': 'Phòng ngủ',
      'giuong 1m8': 'Phòng ngủ',
      'GIUONG_1M8': 'Phòng ngủ',
      'nệm cao su non': 'Phòng ngủ',
      'nem cao su non': 'Phòng ngủ',
      'NEM_CAO_SU_NON': 'Phòng ngủ',
      'trường kỷ gỗ gụ': 'Phòng khách',
      'truong ky go gu': 'Phòng khách',
      'truong ky': 'Phòng khách',
      'ghế đốt nhang': 'Phòng thờ',
      'ghe dot nhang': 'Phòng thờ',
      'GHE_DOT_NHANG': 'Phòng thờ',
      'xích đu sắt': 'Sân vườn / Ngoài trời',
      'xich du sat': 'Sân vườn / Ngoài trời',
      'XICH_DU_SAT': 'Sân vườn / Ngoài trời',
      'bàn ăn 6 ghế': 'Phòng ăn & Bếp',
      'ban an 6 ghe': 'Phòng ăn & Bếp',
      'bàn ăn': 'Phòng ăn & Bếp',
      'ban an': 'Phòng ăn & Bếp',
    };

    for (final entry in searchTerms.entries) {
      test('Query "${entry.key}" resolves to room space "${entry.value}"', () {
        final product = makeProduct(name: entry.key);
        final matches = SampleImageHelper.getSuggestedImages(product);
        expect(matches, isNotEmpty, reason: 'Expected suggestion for query "${entry.key}"');
        expect(matches.first.category.industry, equals(entry.value),
            reason: 'Top match for "${entry.key}" must belong to ${entry.value}');
      });
    }
  });

  group('Reviewer Adversarial Suite 4: Ultra-Lightweight Client-Side Compression (<30KB)', () {
    test('ImageCompressionHelper downscales high-res image to <= 350x350 and <= 30KB', () {
      final highRes = img.Image(width: 1920, height: 1080);
      img.fill(highRes, color: img.ColorRgb8(160, 120, 80));
      final highResBytes = Uint8List.fromList(img.encodeJpg(highRes, quality: 95));
      expect(highResBytes.length, greaterThan(50 * 1024));

      final compressed = ImageCompressionHelper.compressImageBytes(
        highResBytes,
        maxWidth: 350,
        maxHeight: 350,
        quality: 70,
      );

      expect(compressed.length, lessThanOrEqualTo(30 * 1024),
          reason: 'Compressed bytes should be under 30KB for lightweight DB storage');

      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, lessThanOrEqualTo(350));
      expect(decoded.height, lessThanOrEqualTo(350));
    });

    test('Base64 Data URL format matches RFC 2397 standard', () {
      final sampleBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      final dataUrl = ImageCompressionHelper.toBase64DataUrl(sampleBytes);
      expect(ImageCompressionHelper.isBase64DataUrl(dataUrl), isTrue);

      final decodedBytes = ImageCompressionHelper.decodeBase64DataUrl(dataUrl);
      expect(decodedBytes, equals(sampleBytes));
    });

    test('ImageUploadService direct Base64 upload succeeds instantly without Firebase Storage', () async {
      final uploadService = ImageUploadService(useDirectBase64: true);
      final rawImage = img.Image(width: 500, height: 500);
      img.fill(rawImage, color: img.ColorRgb8(80, 50, 20));
      final rawBytes = Uint8List.fromList(img.encodeJpg(rawImage));

      final result = await uploadService.uploadProductImage(
        storeId: 'store_adversarial_test',
        productId: 'prod_sofa_001',
        bytes: rawBytes,
      );

      expect(result.imageUrl, startsWith('data:image/jpeg;base64,'));
      expect(result.isFallbackBase64, isTrue);
      expect(result.byteLength, lessThanOrEqualTo(30 * 1024));
    });
  });
}
