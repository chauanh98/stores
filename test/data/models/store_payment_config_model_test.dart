import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/models/store_payment_config_model.dart';
import 'package:stores/domain/entities/store_payment_config.dart';

void main() {
  group('StorePaymentConfigModel Tests', () {
    const testModel = StorePaymentConfigModel(
      storeId: 'store_001',
      storeName: 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG',
      address: 'Chợ Cờ Đỏ, Xã Cờ Đỏ, Cần Thơ',
      phone: '0917.865 300',
      bankName: 'VIETINBANK',
      bankId: 'vietinbank',
      accountNo: '0917865300',
      accountName: 'Huỳnh Lê Khánh Đăng',
      footerNote: 'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG',
      paperSize: 'k80',
      showVietQR: true,
    );

    test('toMap serializes all fields correctly', () {
      final map = testModel.toMap();

      expect(map['storeId'], 'store_001');
      expect(map['storeName'], 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG');
      expect(map['address'], 'Chợ Cờ Đỏ, Xã Cờ Đỏ, Cần Thơ');
      expect(map['phone'], '0917.865 300');
      expect(map['bankName'], 'VIETINBANK');
      expect(map['bankId'], 'vietinbank');
      expect(map['accountNo'], '0917865300');
      expect(map['accountName'], 'Huỳnh Lê Khánh Đăng');
      expect(map['footerNote'], 'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG');
      expect(map['paperSize'], 'k80');
      expect(map['showVietQR'], isTrue);
    });

    test('fromMap deserializes map with fallback storeId', () {
      final rawMap = {
        'storeName': 'Chi nhánh 2',
        'address': 'Quận Ninh Kiều',
        'paperSize': 'k58',
        'showVietQR': false,
      };

      final model = StorePaymentConfigModel.fromMap(rawMap, 'store_fallback');

      expect(model.storeId, 'store_fallback');
      expect(model.storeName, 'Chi nhánh 2');
      expect(model.address, 'Quận Ninh Kiều');
      expect(model.paperSize, 'k58');
      expect(model.showVietQR, isFalse);
    });

    test('toDomain and fromDomain conversions', () {
      const entity = StorePaymentConfig(
        storeId: 'store_002',
        storeName: 'Cửa hàng Gỗ Mỹ Nghệ',
        address: 'Thới Bình, Cần Thơ',
        phone: '0939.865 300',
        bankName: 'VIETCOMBANK',
        bankId: 'vietcombank',
        accountNo: '123456789',
        accountName: 'TRAN VAN B',
        footerNote: 'Cảm ơn quý khách!',
        paperSize: 'a4',
        showVietQR: false,
      );

      final model = StorePaymentConfigModel.fromDomain(entity);
      final backToDomain = model.toDomain();

      expect(backToDomain, equals(entity));
      expect(backToDomain.paperSize, 'a4');
      expect(backToDomain.showVietQR, isFalse);
    });

    test('Equality and copyWith', () {
      final copy = testModel.copyWith(paperSize: 'a4', showVietQR: false);
      expect(copy.paperSize, 'a4');
      expect(copy.showVietQR, isFalse);
      expect(copy.storeName, testModel.storeName);

      final identicalModel = StorePaymentConfigModel.fromDomain(testModel.toDomain());
      expect(identicalModel, equals(testModel));
      expect(identicalModel.hashCode, equals(testModel.hashCode));
    });
  });
}
