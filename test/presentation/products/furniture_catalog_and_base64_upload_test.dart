import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stores/application/products/services/image_upload_service.dart';
import 'package:stores/core/utils/image_compression_helper.dart';
import 'package:stores/core/utils/sample_image_helper.dart';
import 'package:stores/domain/entities/product.dart';
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
      id: 'p_test',
      code: 'SP001',
      name: name,
      category: category,
      brand: brand,
      category3Levels: category3Levels,
      isCombo: isCombo,
      price: 1000000,
      costPrice: 800000,
      branchStocks: const {},
      unit: 'cái',
      barcode: '123456',
    );
  }

  group('R1. Default Lightweight Client-side Base64 Storage (Phương án 1)', () {
    test('ImageUploadService defaults to useDirectBase64 = true', () {
      final service = ImageUploadService();
      expect(service.useDirectBase64, isTrue);
    });

    test('uploadProductImage produces lightweight Base64 Data URL without Firebase Storage', () async {
      final service = ImageUploadService();

      // Create a valid 400x400 test image using image package
      final testImg = img.Image(width: 400, height: 400);
      img.fill(testImg, color: img.ColorRgb8(120, 80, 40));
      final dummyBytes = Uint8List.fromList(img.encodeJpg(testImg));

      final result = await service.uploadProductImage(
        storeId: 'store_001',
        productId: 'prod_wood_001',
        bytes: dummyBytes,
      );

      expect(result.imageUrl, startsWith('data:image/jpeg;base64,'));
      expect(result.isFallbackBase64, isTrue);

      // Verify size is lightweight (< 40KB)
      final base64Content = result.imageUrl.split(',').last;
      final decoded = base64Decode(base64Content);
      expect(decoded.length, lessThanOrEqualTo(40 * 1024));
    });

    test('ImageCompressionHelper compressImageBytes compresses to < 30KB', () async {
      final testImg = img.Image(width: 600, height: 600);
      img.fill(testImg, color: img.ColorRgb8(100, 150, 200));
      final dummyBytes = Uint8List.fromList(img.encodeJpg(testImg, quality: 95));

      final compressed = ImageCompressionHelper.compressImageBytes(
        dummyBytes,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      expect(compressed.length, lessThanOrEqualTo(30 * 1024));
      final dataUri = ImageCompressionHelper.toBase64DataUrl(compressed);
      expect(dataUri, startsWith('data:image/jpeg;base64,'));
    });
  });

  group('R2. 100% Furniture & Home Woodcraft Catalog across 6 Room Spaces', () {
    test('catalog contains strictly the 6 Room Spaces', () {
      final expectedRooms = [
        'Phòng khách',
        'Phòng ngủ',
        'Phòng ăn & Bếp',
        'Phòng làm việc',
        'Phòng thờ',
        'Sân vườn / Ngoài trời',
      ];

      expect(SampleImageHelper.roomOrder, equals(expectedRooms));
      expect(SampleImageHelper.industries, equals(expectedRooms));

      final actualIndustries = SampleImageHelper.catalog.map((c) => c.industry).toSet();
      expect(actualIndustries, equals(expectedRooms.toSet()));
    });

    test('catalog has zero non-furniture items (no beverages, food, cosmetics, diapers, pets)', () {
      for (final cat in SampleImageHelper.catalog) {
        expect(cat.id.startsWith('beverage_'), isFalse, reason: '${cat.id} should not be in furniture catalog');
        expect(cat.id.startsWith('food_'), isFalse, reason: '${cat.id} should not be in furniture catalog');
        expect(cat.id.startsWith('cosmetics_'), isFalse, reason: '${cat.id} should not be in furniture catalog');
        expect(cat.id.startsWith('baby_'), isFalse, reason: '${cat.id} should not be in furniture catalog');
        expect(cat.id.startsWith('pet_'), isFalse, reason: '${cat.id} should not be in furniture catalog');
        expect(cat.id.startsWith('pharma_'), isFalse, reason: '${cat.id} should not be in furniture catalog');
        expect(cat.id.startsWith('fmcg_'), isFalse, reason: '${cat.id} should not be in furniture catalog');
        expect(cat.id.startsWith('fashion_'), isFalse, reason: '${cat.id} should not be in furniture catalog');
      }
    });

    test('All 7 key furniture terms match their exact corresponding categories (Accented & Unaccented)', () {
      // 1. "Bàn ăn 6 ghế" -> furniture_dining_living_tables (Phòng ăn & Bếp)
      final p1Acc = makeProduct(name: 'Bàn ăn 6 ghế mặt đá');
      final m1Acc = SampleImageHelper.getSuggestedImages(p1Acc);
      expect(m1Acc.first.id, equals('furniture_dining_living_tables'));
      expect(m1Acc.first.industry, equals('Phòng ăn & Bếp'));

      final p1Unacc = makeProduct(name: 'ban an 6 ghe mat da');
      final m1Unacc = SampleImageHelper.getSuggestedImages(p1Unacc);
      expect(m1Unacc.first.id, equals('furniture_dining_living_tables'));

      // 2. "Sofa góc L" -> furniture_sofas_living (Phòng khách)
      final p2Acc = makeProduct(name: 'Sofa góc L bọc nỉ');
      final m2Acc = SampleImageHelper.getSuggestedImages(p2Acc);
      expect(m2Acc.first.id, equals('furniture_sofas_living'));
      expect(m2Acc.first.industry, equals('Phòng khách'));

      final p2Unacc = makeProduct(name: 'sofa goc l boc ni');
      final m2Unacc = SampleImageHelper.getSuggestedImages(p2Unacc);
      expect(m2Unacc.first.id, equals('furniture_sofas_living'));

      // 3. "Giường ngủ 1m8" -> home_bedding_mattress (Phòng ngủ)
      final p3Acc = makeProduct(name: 'Giường ngủ 1m8 gỗ sồi Nga');
      final m3Acc = SampleImageHelper.getSuggestedImages(p3Acc);
      expect(m3Acc.first.id, equals('home_bedding_mattress'));
      expect(m3Acc.first.industry, equals('Phòng ngủ'));

      final p3Unacc = makeProduct(name: 'giuong ngu 1m8 go soi');
      final m3Unacc = SampleImageHelper.getSuggestedImages(p3Unacc);
      expect(m3Unacc.first.id, equals('home_bedding_mattress'));

      // 4. "Nệm cao su non" -> home_bedding_mattress (Phòng ngủ)
      final p4Acc = makeProduct(name: 'Nệm cao su non Thắng Lợi');
      final m4Acc = SampleImageHelper.getSuggestedImages(p4Acc);
      expect(m4Acc.first.id, equals('home_bedding_mattress'));
      expect(m4Acc.first.industry, equals('Phòng ngủ'));

      final p4Unacc = makeProduct(name: 'nem cao su non thang loi');
      final m4Unacc = SampleImageHelper.getSuggestedImages(p4Unacc);
      expect(m4Unacc.first.id, equals('home_bedding_mattress'));

      // 5. "Tủ thờ gỗ" -> altar_ancestral_cabinet (Phòng thờ)
      final p5Acc = makeProduct(name: 'Tủ thờ gỗ gõ đỏ gia tiên');
      final m5Acc = SampleImageHelper.getSuggestedImages(p5Acc);
      expect(m5Acc.first.id, equals('altar_ancestral_cabinet'));
      expect(m5Acc.first.industry, equals('Phòng thờ'));

      final p5Unacc = makeProduct(name: 'tu tho go go do gia tien');
      final m5Unacc = SampleImageHelper.getSuggestedImages(p5Unacc);
      expect(m5Unacc.first.id, equals('altar_ancestral_cabinet'));

      // 6. "Xích đu sắt" -> outdoor_swing_wrought_iron (Sân vườn / Ngoài trời)
      final p6Acc = makeProduct(name: 'Xích đu sắt nghệ thuật ngoài trời');
      final m6Acc = SampleImageHelper.getSuggestedImages(p6Acc);
      expect(m6Acc.first.id, equals('outdoor_swing_wrought_iron'));
      expect(m6Acc.first.industry, equals('Sân vườn / Ngoài trời'));

      final p6Unacc = makeProduct(name: 'xich du sat ngoai troi');
      final m6Unacc = SampleImageHelper.getSuggestedImages(p6Unacc);
      expect(m6Unacc.first.id, equals('outdoor_swing_wrought_iron'));

      // 7. "Ghế đốt nhang" -> altar_incense_chair (Phòng thờ)
      final p7Acc = makeProduct(name: 'Ghế đốt nhang gỗ tràm có tay vịn');
      final m7Acc = SampleImageHelper.getSuggestedImages(p7Acc);
      expect(m7Acc.first.id, equals('altar_incense_chair'));
      expect(m7Acc.first.industry, equals('Phòng thờ'));

      final p7Unacc = makeProduct(name: 'ghe dot nhang go tram');
      final m7Unacc = SampleImageHelper.getSuggestedImages(p7Unacc);
      expect(m7Unacc.first.id, equals('altar_incense_chair'));
    });
  });

  group('R3. SampleImagePickerDialog Widget Tests', () {
    testWidgets('Dialog displays filter chips for Tất cả nội thất and 6 room spaces', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () {
                    SampleImagePickerDialog.show(
                      context,
                      productName: 'Bàn ăn 6 ghế',
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Check header title
      expect(find.text('Gợi ý & Chọn Ảnh Mẫu Thông Minh'), findsOneWidget);

      // Check search bar hint
      expect(find.text('Tìm kiếm nội thất (sofa, nệm, bàn ăn, tủ thờ...)'), findsOneWidget);

      // Check initial Filter Chips specifically as ChoiceChips
      expect(find.widgetWithText(ChoiceChip, 'Tất cả nội thất'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Phòng khách'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Phòng ngủ'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Phòng ăn & Bếp'), findsOneWidget);

      // Drag horizontal chip list to reveal remaining chips
      await tester.drag(find.widgetWithText(ChoiceChip, 'Phòng khách'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Phòng làm việc'), findsOneWidget);

      await tester.drag(find.widgetWithText(ChoiceChip, 'Phòng làm việc'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Phòng thờ'), findsOneWidget);

      await tester.drag(find.widgetWithText(ChoiceChip, 'Phòng thờ'), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(ChoiceChip, 'Sân vườn / Ngoài trời'), findsOneWidget);

      // Verify no non-furniture chips exist
      expect(find.widgetWithText(ChoiceChip, 'Đồ uống & Giải khát'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Mỹ phẩm'), findsNothing);
      expect(find.widgetWithText(ChoiceChip, 'Thực phẩm'), findsNothing);

      // Tap on "Phòng thờ" chip
      await tester.tap(find.widgetWithText(ChoiceChip, 'Phòng thờ'));
      await tester.pumpAndSettle();

      // In "Phòng thờ", verify items such as "Tủ thờ gia tiên gỗ gõ đỏ/gụ" or "Ghế cao thắp nhang"
      expect(find.text('Tủ thờ gia tiên gỗ gõ đỏ/gụ'), findsOneWidget);
      expect(find.text('Ghế cao thắp nhang (Ghế đốt nhang gỗ có tay vịn)'), findsOneWidget);
    });

    testWidgets('Selecting a sample image returns its URL', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      String? pickedUrl;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    pickedUrl = await SampleImagePickerDialog.show(
                      context,
                      productName: 'Sofa góc L',
                    );
                  },
                  child: const Text('Open Dialog'),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Find suggested card
      final sofaCard = find.text('Sofa nỉ góc chữ L & Sofa da, Sofa bed');
      expect(sofaCard, findsWidgets);

      await tester.tap(sofaCard.first);
      await tester.pumpAndSettle();

      expect(pickedUrl, isNotNull);
      expect(pickedUrl, startsWith('https://images.unsplash.com/'));
    });
  });
}
