import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stores/application/products/services/image_upload_service.dart';
import 'package:stores/core/utils/image_compression_helper.dart';

void main() {
  group('ImageUploadService Unit Tests', () {
    Uint8List createSampleImageBytes(int width, int height) {
      final image = img.Image(width: width, height: height);
      img.fill(image, color: img.ColorRgb8(0, 150, 255));
      return Uint8List.fromList(img.encodeJpg(image, quality: 85));
    }

    test('Candidate buckets include default firebasestorage.app and fallback appspot.com', () {
      final service = ImageUploadService();
      expect(
        service.candidateBuckets,
        containsAll([
          'khanh-dang-store.firebasestorage.app',
          'khanh-dang-store.appspot.com',
        ]),
      );
    });

    test('uploadProductImage automatically falls back to compressed Base64 Data URL when storage throws', () async {
      // Khi chạy test môi trường không có Firebase app, FirebaseStorage.instanceFor sẽ ném ngoại lệ
      // ImageUploadService phải bắt an toàn ngoại lệ này và fallback sang nén Base64
      final service = ImageUploadService();
      final sampleBytes = createSampleImageBytes(640, 480);

      final result = await service.uploadProductImage(
        storeId: 'store_001',
        productId: 'prod_test_fallback',
        bytes: sampleBytes,
      );

      expect(result.isFallbackBase64, isTrue);
      expect(result.imageUrl, isNotEmpty);
      expect(result.imageUrl.startsWith('data:image/jpeg;base64,'), isTrue);
      expect(result.isStorageUrl, isFalse);

      // Giải mã dữ liệu và kiểm tra kích thước đã được nén tối đa 300x300
      final decodedBytes = ImageCompressionHelper.decodeBase64DataUrl(result.imageUrl);
      expect(decodedBytes, isNotNull);
      final decodedImage = img.decodeImage(decodedBytes!);
      expect(decodedImage, isNotNull);
      expect(decodedImage!.width, equals(300));
      expect(decodedImage.height, equals(225));
    });

    test('uploadProductImage returns empty result when no image bytes or file provided', () async {
      final service = ImageUploadService();
      final result = await service.uploadProductImage(
        storeId: 'store_001',
        productId: 'prod_empty',
        bytes: null,
        file: null,
      );

      expect(result.imageUrl, isEmpty);
      expect(result.isFallbackBase64, isFalse);
      expect(result.errorMessage, isNotNull);
    });

    test('deleteProductImage safely ignores Base64 Data URLs without touching Cloud Storage', () async {
      final service = ImageUploadService();
      final base64Url = 'data:image/jpeg;base64,${base64Encode([1, 2, 3])}';

      // Không được ném bất kỳ ngoại lệ nào
      await expectLater(service.deleteProductImage(base64Url), completes);
      await expectLater(service.deleteProductImage(null), completes);
      await expectLater(service.deleteProductImage(''), completes);
    });

    test('deleteProductImage catches and swallows any storage errors on network URLs', () async {
      final service = ImageUploadService();
      // URL mạng khi không có Firebase app sẽ ném ngoại lệ trong FirebaseStorage, nhưng service phải swallow an toàn
      await expectLater(
        service.deleteProductImage('https://firebasestorage.googleapis.com/v0/b/test/o/img.jpg'),
        completes,
      );
    });

    testWidgets('showStorageActivationGuide displays dialog with step-by-step instructions', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ImageUploadService.showStorageActivationGuide(context),
                child: const Text('Open Guide'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Guide'));
      await tester.pumpAndSettle();

      expect(find.text('Kích hoạt Firebase Storage'), findsOneWidget);
      expect(find.textContaining('console.firebase.google.com'), findsOneWidget);
      expect(find.textContaining('khanh-dang-store'), findsOneWidget);
      expect(find.text('Đã hiểu'), findsOneWidget);

      await tester.tap(find.text('Đã hiểu'));
      await tester.pumpAndSettle();

      expect(find.text('Kích hoạt Firebase Storage'), findsNothing);
    });

    test('uploadProductImage returns empty result when empty byte array is passed', () async {
      final service = ImageUploadService();
      final result = await service.uploadProductImage(
        storeId: 'store_001',
        productId: 'prod_empty_bytes',
        bytes: Uint8List(0),
      );

      expect(result.imageUrl, isEmpty);
      expect(result.isFallbackBase64, isFalse);
      expect(result.errorMessage, contains('Không có dữ liệu ảnh'));
    });

    test('deleteProductImage safely handles multi-URL string containing both network and base64 URLs', () async {
      final service = ImageUploadService();
      final b64 = 'data:image/jpeg;base64,${base64Encode([1, 2, 3])}';
      final mixed = 'https://firebasestorage.googleapis.com/v0/b/test/o/img1.jpg, $b64, https://firebasestorage.googleapis.com/v0/b/test/o/img2.jpg';

      await expectLater(service.deleteProductImage(mixed), completes);
    });
  });
}
