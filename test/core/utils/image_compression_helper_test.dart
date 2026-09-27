import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:stores/core/utils/image_compression_helper.dart';

void main() {
  group('ImageCompressionHelper Unit Tests', () {
    // Helper để tạo ảnh mẫu dạng byte
    Uint8List createSampleImageBytes(int width, int height) {
      final image = img.Image(width: width, height: height);
      // Vẽ một màu đơn giản
      img.fill(image, color: img.ColorRgb8(255, 100, 50));
      return Uint8List.fromList(img.encodeJpg(image, quality: 90));
    }

    test(
        'compressImageBytes resizes landscape image to max 300x300 maintaining aspect ratio',
        () {
      final originalBytes = createSampleImageBytes(800, 600); // 4:3 landscape
      final compressed = ImageCompressionHelper.compressImageBytes(
        originalBytes,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      expect(compressed, isNotEmpty);
      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(300));
      expect(decoded.height, equals(225)); // 600 * (300 / 800) = 225
      expect(compressed.length, lessThan(originalBytes.length));
    });

    test(
        'compressImageBytes resizes portrait image to max 300x300 maintaining aspect ratio',
        () {
      final originalBytes = createSampleImageBytes(600, 800); // 3:4 portrait
      final compressed = ImageCompressionHelper.compressImageBytes(
        originalBytes,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      expect(compressed, isNotEmpty);
      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.height, equals(300));
      expect(decoded.width, equals(225)); // 600 * (300 / 800) = 225
    });

    test('compressImageBytes resizes square image to 300x300', () {
      final originalBytes = createSampleImageBytes(500, 500);
      final compressed = ImageCompressionHelper.compressImageBytes(
        originalBytes,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      expect(compressed, isNotEmpty);
      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(300));
      expect(decoded.height, equals(300));
    });

    test('compressImageBytes does not upscale images smaller than max bounds',
        () {
      final originalBytes = createSampleImageBytes(150, 100);
      final compressed = ImageCompressionHelper.compressImageBytes(
        originalBytes,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(150));
      expect(decoded.height, equals(100));
    });

    test('compressImageBytes gracefully handles empty or corrupted bytes', () {
      final empty = Uint8List(0);
      expect(ImageCompressionHelper.compressImageBytes(empty), equals(empty));

      final corrupted = Uint8List.fromList([1, 2, 3, 4, 5]);
      final result = ImageCompressionHelper.compressImageBytes(corrupted);
      expect(result, equals(corrupted));
    });

    test('toBase64DataUrl produces standard Data URI format', () {
      final sample = Uint8List.fromList([10, 20, 30]);
      final dataUrl = ImageCompressionHelper.toBase64DataUrl(sample);

      expect(dataUrl.startsWith('data:image/jpeg;base64,'), isTrue);
      expect(dataUrl, equals('data:image/jpeg;base64,${base64Encode(sample)}'));
    });

    test('isBase64DataUrl accurately identifies Data URIs', () {
      expect(ImageCompressionHelper.isBase64DataUrl(null), isFalse);
      expect(ImageCompressionHelper.isBase64DataUrl(''), isFalse);
      expect(
          ImageCompressionHelper.isBase64DataUrl('https://example.com/img.jpg'),
          isFalse);
      expect(
          ImageCompressionHelper.isBase64DataUrl('http://example.com/img.jpg'),
          isFalse);
      expect(
          ImageCompressionHelper.isBase64DataUrl(
              'data:image/jpeg;base64,ABCDEF=='),
          isTrue);
      expect(
          ImageCompressionHelper.isBase64DataUrl(
              'data:image/png;base64,ABCDEF=='),
          isTrue);
      expect(
          ImageCompressionHelper.isBase64DataUrl(
              '  data:image/jpeg;base64,ABCDEF==  '),
          isTrue);
    });

    test(
        'decodeBase64DataUrl safely decodes valid Data URIs and catches errors',
        () {
      final originalBytes = Uint8List.fromList([65, 66, 67, 68]); // "ABCD"
      final dataUrl = ImageCompressionHelper.toBase64DataUrl(originalBytes);

      final decoded = ImageCompressionHelper.decodeBase64DataUrl(dataUrl);
      expect(decoded, equals(originalBytes));

      // Invalid format returns null
      expect(
          ImageCompressionHelper.decodeBase64DataUrl('https://foo.com/bar.jpg'),
          isNull);
      expect(
          ImageCompressionHelper.decodeBase64DataUrl(
              'data:image/jpeg;base64,NOT_VALID_BASE64!@#'),
          isNull);
      expect(
          ImageCompressionHelper.decodeBase64DataUrl('data:image/jpeg;base64'),
          isNull);
      expect(ImageCompressionHelper.decodeBase64DataUrl(null), isNull);
    });

    test('formatByteSize formats byte sizes readably', () {
      expect(ImageCompressionHelper.formatByteSize(500), equals('500 B'));
      expect(ImageCompressionHelper.formatByteSize(15360), equals('15.0 KB'));
      expect(ImageCompressionHelper.formatByteSize(1048576), equals('1.00 MB'));
    });

    test(
        'compressImageBytes downscales large high-res photo to <= 300x300 and < 30KB',
        () {
      final highResBytes = createSampleImageBytes(2400, 1800);
      expect(highResBytes.length, greaterThan(50000));

      final compressed = ImageCompressionHelper.compressImageBytes(
        highResBytes,
        maxWidth: 300,
        maxHeight: 300,
        quality: 70,
      );

      expect(compressed, isNotEmpty);
      final decoded = img.decodeImage(compressed);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(300));
      expect(decoded.height, equals(225));
      expect(compressed.length, lessThan(30720)); // < 30KB
    });

    test(
        'parseImageUrls preserves Base64 Data URL intact with internal comma when mixed with network URLs',
        () {
      final base64Payload =
          base64Encode(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]));
      final base64Url = 'data:image/jpeg;base64,$base64Payload';
      final mixedString =
          'https://storage.googleapis.com/img1.jpg, $base64Url, https://storage.googleapis.com/img2.jpg';

      final parsed = ImageCompressionHelper.parseImageUrls(mixedString);
      expect(parsed.length, equals(3));
      expect(parsed[0], equals('https://storage.googleapis.com/img1.jpg'));
      expect(parsed[1], equals(base64Url));
      expect(parsed[2], equals('https://storage.googleapis.com/img2.jpg'));
    });

    test(
        'parseImageUrls handles multiple Base64 Data URLs separated by comma without corrupting either',
        () {
      const b1 = 'data:image/jpeg;base64,AAAA';
      const b2 = 'data:image/png;base64,BBBB';
      const mixed = '$b1, $b2';

      final parsed = ImageCompressionHelper.parseImageUrls(mixed);
      expect(parsed.length, equals(2));
      expect(parsed[0], equals(b1));
      expect(parsed[1], equals(b2));
    });

    test('resolvePrimaryUrl extracts the first valid URL from any mixed string',
        () {
      const b1 = 'data:image/jpeg;base64,AAAA';
      expect(
          ImageCompressionHelper.resolvePrimaryUrl(
              'https://foo.com/bar.jpg, $b1'),
          equals('https://foo.com/bar.jpg'));
      expect(
          ImageCompressionHelper.resolvePrimaryUrl(
              '$b1, https://foo.com/bar.jpg'),
          equals(b1));
      expect(ImageCompressionHelper.resolvePrimaryUrl(null), isNull);
      expect(ImageCompressionHelper.resolvePrimaryUrl('   '), isNull);
    });
  });
}
