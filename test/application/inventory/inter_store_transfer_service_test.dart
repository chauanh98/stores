import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/inventory/inter_store_transfer_service.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  const sampleProduct = Product(
    id: 'prod_001',
    name: 'Sản phẩm Test',
    code: 'SP001',
    barcode: '893000000001',
    brand: 'BrandA',
    model: 'ModelX',
    price: 500000,
    costPrice: 350000,
    branchStocks: {'branch_1': 20, 'branch_2': 0},
    category: 'Thực phẩm',
  );

  group('InterStoreTransferService Unit Tests', () {
    test('Validates negative or zero transfer quantity', () async {
      // InterStoreTransferService with mock/null db for pure validation check before DB query
      // Notice: InterStoreTransferService checks quantity <= 0 before calling DB
      // We can pass a dummy FirebaseDatabase instance or test service logic
      final service = InterStoreTransferService(null);

      final errorZero = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: 0,
      );
      expect(errorZero, equals('Số lượng phải lớn hơn 0'));

      final errorNeg = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: -5,
      );
      expect(errorNeg, equals('Số lượng phải lớn hơn 0'));
    });

    test('Validates insufficient stock', () async {
      final service = InterStoreTransferService(null);

      final error = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: 25, // Product stock is 20
      );
      expect(error, equals('Không đủ số lượng trong kho'));
    });

    test('Validates same source and target store transfer', () async {
      final service = InterStoreTransferService(null);

      final error = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: 'store_001',
        product: sampleProduct,
        quantity: 5,
      );
      expect(error, equals('Không thể chuyển cùng kho'));
    });

    test('Validates empty store ID parameters', () async {
      final service = InterStoreTransferService(null);

      final errorEmptySource = await service.transferProduct(
        sourceStoreId: '',
        targetStoreId: 'store_002',
        product: sampleProduct,
        quantity: 5,
      );
      expect(errorEmptySource, equals('Chi nhánh không hợp lệ'));

      final errorEmptyTarget = await service.transferProduct(
        sourceStoreId: 'store_001',
        targetStoreId: '',
        product: sampleProduct,
        quantity: 5,
      );
      expect(errorEmptyTarget, equals('Chi nhánh không hợp lệ'));
    });
  });
}
