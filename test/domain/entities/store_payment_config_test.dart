import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:stores/domain/entities/store_payment_config.dart';

void main() {
  group('StorePaymentConfig Entity Tests', () {
    test('Default values and format resolution', () {
      const config = StorePaymentConfig(storeId: 'store_001');

      expect(config.storeId, 'store_001');
      expect(config.storeName, 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG');
      expect(config.paperSize, 'k80');
      expect(config.showVietQR, isTrue);
      expect(config.isK80, isTrue);
      expect(config.isK58, isFalse);
      expect(config.isA4, isFalse);
      expect(config.resolvedPageFormat, PdfPageFormat.roll80);
    });

    test('Format helper getters for K58 and A4', () {
      const configK58 = StorePaymentConfig(
        storeId: 'store_001',
        paperSize: 'k58',
      );
      expect(configK58.isK58, isTrue);
      expect(configK58.isK80, isFalse);
      expect(configK58.isA4, isFalse);
      expect(configK58.resolvedPageFormat, PdfPageFormat.roll57);

      const configA4 = StorePaymentConfig(
        storeId: 'store_001',
        paperSize: 'a4',
      );
      expect(configA4.isA4, isTrue);
      expect(configA4.isK80, isFalse);
      expect(configA4.isK58, isFalse);
      expect(configA4.resolvedPageFormat, PdfPageFormat.a4);
    });

    test('copyWith properly updates fields', () {
      const original = StorePaymentConfig(
        storeId: 'store_001',
        storeName: 'Cửa hàng Gốc',
        paperSize: 'k80',
        showVietQR: true,
      );

      final updated = original.copyWith(
        storeName: 'Cửa hàng Mới',
        paperSize: 'k58',
        showVietQR: false,
      );

      expect(updated.storeId, 'store_001');
      expect(updated.storeName, 'Cửa hàng Mới');
      expect(updated.paperSize, 'k58');
      expect(updated.showVietQR, isFalse);
      expect(updated.address, original.address);
    });

    test('toMap and fromMap roundtrip', () {
      const config = StorePaymentConfig(
        storeId: 'store_002',
        storeName: 'Nội thất Cao Cấp',
        address: '123 Đường 30/4, Cần Thơ',
        phone: '0901234567',
        bankName: 'MBBANK',
        bankId: 'mbbank',
        accountNo: '88889999',
        accountName: 'NGUYEN VAN A',
        footerNote: 'Xin cảm ơn quý khách!',
        paperSize: 'a4',
        showVietQR: false,
      );

      final map = config.toMap();
      final fromMapConfig = StorePaymentConfig.fromMap('store_002', map);

      expect(fromMapConfig, equals(config));
      expect(fromMapConfig.hashCode, equals(config.hashCode));
    });

    test('fromMap with null and missing fields handles defaults safely', () {
      final configNull = StorePaymentConfig.fromMap('store_003', null);
      expect(configNull.storeId, 'store_003');
      expect(configNull.paperSize, 'k80');
      expect(configNull.showVietQR, isTrue);

      final configMissing = StorePaymentConfig.fromMap('store_003', {
        'storeName': 'Custom Name',
      });
      expect(configMissing.storeName, 'Custom Name');
      expect(configMissing.paperSize, 'k80');
      expect(configMissing.showVietQR, isTrue);
    });

    test('Value equality and hash code', () {
      const config1 = StorePaymentConfig(
        storeId: 'store_001',
        paperSize: 'k80',
        showVietQR: true,
      );
      const config2 = StorePaymentConfig(
        storeId: 'store_001',
        paperSize: 'k80',
        showVietQR: true,
      );
      const config3 = StorePaymentConfig(
        storeId: 'store_001',
        paperSize: 'k58',
        showVietQR: true,
      );

      expect(config1, equals(config2));
      expect(config1.hashCode, equals(config2.hashCode));
      expect(config1, isNot(equals(config3)));
    });
  });
}
