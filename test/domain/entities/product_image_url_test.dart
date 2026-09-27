import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  group('Product Image URL Resolution Tests', () {
    test('allImageUrls and primaryImageUrl handle single network URL', () {
      const product = Product(
        id: 'p1',
        name: 'Sản phẩm 1',
        code: 'SP01',
        price: 100000,
        costPrice: 70000,
        branchStocks: {'store_001': 10},
        category: 'Chung',
        imageUrl: 'https://example.com/images/prod1.jpg',
      );

      expect(product.allImageUrls, equals(['https://example.com/images/prod1.jpg']));
      expect(product.primaryImageUrl, equals('https://example.com/images/prod1.jpg'));
    });

    test('allImageUrls and primaryImageUrl handle comma-separated multiple network URLs', () {
      const product = Product(
        id: 'p2',
        name: 'Sản phẩm 2',
        code: 'SP02',
        price: 100000,
        costPrice: 70000,
        branchStocks: {'store_001': 10},
        category: 'Chung',
        imageUrl: 'https://example.com/1.jpg, https://example.com/2.jpg , http://example.com/3.jpg',
      );

      expect(
        product.allImageUrls,
        equals([
          'https://example.com/1.jpg',
          'https://example.com/2.jpg',
          'http://example.com/3.jpg',
        ]),
      );
      expect(product.primaryImageUrl, equals('https://example.com/1.jpg'));
    });

    test('allImageUrls preserves Base64 Data URL intact without comma-splitting corruption', () {
      const base64DataUrl =
          'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEASABIAAD/2wBDAP//////////////////////////////////////////////////////////////////////////////////////wgALCAABAAEBAREA/8QAFBABAAAAAAAAAAAAAAAAAAAAAP/aAAgBAQABPxA=';

      const product = Product(
        id: 'p3',
        name: 'Sản phẩm Base64',
        code: 'SP03',
        price: 100000,
        costPrice: 70000,
        branchStocks: {'store_001': 10},
        category: 'Chung',
        imageUrl: base64DataUrl,
      );

      // Tuyệt đối không được tách chuỗi tại dấu phẩy ",/9j/..."
      expect(product.allImageUrls.length, equals(1));
      expect(product.allImageUrls.first, equals(base64DataUrl));
      expect(product.primaryImageUrl, equals(base64DataUrl));
    });

    test('allImageUrls and primaryImageUrl return empty and null when imageUrl is empty or whitespace', () {
      const productEmpty = Product(
        id: 'p4',
        name: 'Sản phẩm Không Ảnh',
        code: 'SP04',
        price: 100000,
        costPrice: 70000,
        branchStocks: {'store_001': 10},
        category: 'Chung',
        imageUrl: '   ',
      );

      expect(productEmpty.allImageUrls, isEmpty);
      expect(productEmpty.primaryImageUrl, isNull);
    });

    test('allImageUrls correctly handles mixed network and Base64 Data URLs without payload truncation', () {
      const b64 = 'data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ==';
      const mixed = Product(
        id: 'p5',
        name: 'Sản phẩm Hỗn Hợp',
        code: 'SP05',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'store_001': 5},
        category: 'Chung',
        imageUrl: 'https://example.com/net1.jpg, $b64, https://example.com/net2.jpg',
      );

      final urls = mixed.allImageUrls;
      expect(urls.length, equals(3));
      expect(urls[0], equals('https://example.com/net1.jpg'));
      expect(urls[1], equals(b64));
      expect(urls[2], equals('https://example.com/net2.jpg'));
      expect(mixed.primaryImageUrl, equals('https://example.com/net1.jpg'));
    });

    test('allImageUrls correctly handles multiple Base64 Data URLs separated by comma', () {
      const b64_1 = 'data:image/jpeg;base64,AAAA';
      const b64_2 = 'data:image/png;base64,BBBB';
      const multiBase64 = Product(
        id: 'p6',
        name: 'Sản phẩm Đa Base64',
        code: 'SP06',
        price: 50000,
        costPrice: 30000,
        branchStocks: {'store_001': 5},
        category: 'Chung',
        imageUrl: '$b64_1, $b64_2',
      );

      final urls = multiBase64.allImageUrls;
      expect(urls.length, equals(2));
      expect(urls[0], equals(b64_1));
      expect(urls[1], equals(b64_2));
      expect(multiBase64.primaryImageUrl, equals(b64_1));
    });
  });
}
