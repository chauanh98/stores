import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/models/supplier_model.dart';
import 'package:stores/domain/entities/supplier.dart';

void main() {
  group('SupplierModel Tests', () {
    const testModel = SupplierModel(
      id: 'NCC000001',
      code: 'NCC000001',
      name: 'Công ty Cổ phần Digiworld',
      phone: '02839291234',
      email: 'contact@digiworld.com.vn',
      address: '195 Cô Bắc, P. Cô Giang, Q.1, TP.HCM',
      taxCode: '0302861742',
      totalPurchase: 145000000.0,
      currentDebt: 32500000.0,
      note: 'Nhà phân phối chính hãng',
      status: 'active',
      branch: 'store_001',
      createdAt: '2026-05-15T08:00:00.000Z',
      createdBy: 'Admin',
    );

    test('toMap serializes all fields properly', () {
      final map = testModel.toMap();

      expect(map['id'], 'NCC000001');
      expect(map['code'], 'NCC000001');
      expect(map['name'], 'Công ty Cổ phần Digiworld');
      expect(map['phone'], '02839291234');
      expect(map['email'], 'contact@digiworld.com.vn');
      expect(map['address'], '195 Cô Bắc, P. Cô Giang, Q.1, TP.HCM');
      expect(map['taxCode'], '0302861742');
      expect(map['totalPurchase'], 145000000.0);
      expect(map['currentDebt'], 32500000.0);
      expect(map['note'], 'Nhà phân phối chính hãng');
      expect(map['status'], 'active');
      expect(map['branch'], 'store_001');
      expect(map['createdAt'], '2026-05-15T08:00:00.000Z');
      expect(map['createdBy'], 'Admin');
    });

    test('fromMap deserializes map correctly including numeric type conversions', () {
      final rawMap = {
        'id': 'NCC000002',
        'code': 'NCC000002',
        'name': 'Công ty Synnex FPT',
        'phone': '02473006666',
        'email': 'distribution@synnexfpt.com.vn',
        'address': 'Duy Tân, Cầu Giấy, Hà Nội',
        'taxCode': '0103636585',
        'totalPurchase': 98000000, // int in JSON
        'currentDebt': 15200000, // int in JSON
        'note': 'Linh kiện Dell, Asus',
        'status': 'active',
        'branch': 'store_002',
        'createdAt': '2026-06-01T00:00:00.000Z',
        'createdBy': 'Supervisor',
      };

      final model = SupplierModel.fromMap(rawMap);

      expect(model.id, 'NCC000002');
      expect(model.code, 'NCC000002');
      expect(model.name, 'Công ty Synnex FPT');
      expect(model.phone, '02473006666');
      expect(model.email, 'distribution@synnexfpt.com.vn');
      expect(model.address, 'Duy Tân, Cầu Giấy, Hà Nội');
      expect(model.taxCode, '0103636585');
      expect(model.totalPurchase, 98000000.0);
      expect(model.currentDebt, 15200000.0);
      expect(model.note, 'Linh kiện Dell, Asus');
      expect(model.status, 'active');
      expect(model.branch, 'store_002');
      expect(model.createdAt, '2026-06-01T00:00:00.000Z');
      expect(model.createdBy, 'Supervisor');
    });

    test('fromMap handles null and missing fields gracefully', () {
      final minimalMap = <String, dynamic>{
        'id': 'NCC_MIN',
        'name': 'NCC Thiếu Thông Tin',
      };

      final model = SupplierModel.fromMap(minimalMap);

      expect(model.id, 'NCC_MIN');
      expect(model.code, '');
      expect(model.name, 'NCC Thiếu Thông Tin');
      expect(model.phone, '');
      expect(model.email, '');
      expect(model.address, '');
      expect(model.taxCode, isNull);
      expect(model.totalPurchase, 0.0);
      expect(model.currentDebt, 0.0);
      expect(model.note, isNull);
      expect(model.status, 'active');
      expect(model.branch, isNull);
      expect(model.createdAt, isNull);
      expect(model.createdBy, isNull);
    });

    test('toDomain and fromDomain conversions preserve complete entity state', () {
      const domain = Supplier(
        id: 'NCC000003',
        code: 'NCC000003',
        name: 'Samsung Electronics VN',
        phone: '02838217300',
        email: 'b2b@samsung.com',
        address: 'Hải Triều, Q.1, TP.HCM',
        taxCode: '0300401888',
        totalPurchase: 76000000.0,
        currentDebt: 0.0,
        note: 'Điện thoại, tablet',
        status: 'active',
        branch: 'store_001',
        createdAt: '2026-07-01T00:00:00.000Z',
        createdBy: 'Admin',
      );

      final model = SupplierModel.fromDomain(domain);
      final backToDomain = model.toDomain();

      expect(backToDomain, equals(domain));
    });
  });
}
