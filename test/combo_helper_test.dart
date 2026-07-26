import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/combo_helper.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  group('ComboHelper & Combo Product Unit Tests', () {
    late Product tableProduct;
    late Product chairProduct;
    late Product comboProduct;
    late List<Product> allProducts;

    setUp(() {
      // Sản phẩm thành phần 1: Bàn cabin lẻ
      tableProduct = const Product(
        id: 'table_01',
        name: 'Bàn cabin lẻ',
        code: 'BAN-CB',
        price: 1000000,
        costPrice: 700000,
        branchStocks: {'branch_1': 10, 'branch_2': 5},
        category: 'Bàn ghế',
      );

      // Sản phẩm thành phần 2: Ghế cabin lẻ
      chairProduct = const Product(
        id: 'chair_01',
        name: 'Ghế cabin lẻ',
        code: 'GHE-CB',
        price: 300000,
        costPrice: 200000,
        branchStocks: {'branch_1': 20, 'branch_2': 12},
        category: 'Bàn ghế',
      );

      // Sản phẩm Combo: Bộ bàn cabin 6 ghế (1 Bàn + 6 Ghế)
      comboProduct = const Product(
        id: 'combo_01',
        name: 'Bộ bàn cabin 6 ghế',
        code: 'COMBO-CB6',
        price: 2500000,
        costPrice: 1900000,
        branchStocks: {'branch_1': 0, 'branch_2': 0},
        category: 'Bàn ghế',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'table_01',
            productCode: 'BAN-CB',
            productName: 'Bàn cabin lẻ',
            quantity: 1,
            costPrice: 700000,
          ),
          ComboComponent(
            productId: 'chair_01',
            productCode: 'GHE-CB',
            productName: 'Ghế cabin lẻ',
            quantity: 6,
            costPrice: 200000,
          ),
        ],
      );

      allProducts = [tableProduct, chairProduct, comboProduct];
    });

    test('1. Lấy tồn kho sản phẩm đơn lẻ thông thường', () {
      final stockBranch1 = ComboHelper.getAvailableStock(
        product: tableProduct,
        branchId: 'branch_1',
        allProducts: allProducts,
      );
      final stockBranch2 = ComboHelper.getAvailableStock(
        product: tableProduct,
        branchId: 'branch_2',
        allProducts: allProducts,
      );

      expect(stockBranch1, equals(10));
      expect(stockBranch2, equals(5));
    });

    test('2. Tính tồn kho quy đổi cho Combo dựa trên món thành phần (Trường hợp đủ hàng)', () {
      // Chi nhánh 1: Bàn = 10 (10/1 = 10), Ghế = 20 (20/6 = 3.33 -> 3 bộ)
      // Tồn kho Combo tại Chi nhánh 1 = min(10, 3) = 3 bộ
      final comboStockBranch1 = ComboHelper.getAvailableStock(
        product: comboProduct,
        branchId: 'branch_1',
        allProducts: allProducts,
      );

      expect(comboStockBranch1, equals(3));
    });

    test('3. Tính tồn kho quy đổi cho Combo tại Chi nhánh 2', () {
      // Chi nhánh 2: Bàn = 5 (5/1 = 5), Ghế = 12 (12/6 = 2 bộ)
      // Tồn kho Combo tại Chi nhánh 2 = min(5, 2) = 2 bộ
      final comboStockBranch2 = ComboHelper.getAvailableStock(
        product: comboProduct,
        branchId: 'branch_2',
        allProducts: allProducts,
      );

      expect(comboStockBranch2, equals(2));
    });

    test('4. Tính tổng tồn kho khả dụng của Combo ở tất cả các chi nhánh', () {
      // Chi nhánh 1 = 3 bộ, Chi nhánh 2 = 2 bộ -> Tổng tồn = 5 bộ
      final totalStock = ComboHelper.getTotalAvailableStock(
        product: comboProduct,
        allProducts: allProducts,
        branchIds: ['branch_1', 'branch_2'],
      );

      expect(totalStock, equals(5));
    });

    test('5. Tồn kho Combo nhảy về 0 khi 1 sản phẩm linh kiện hết hàng', () {
      // Đặt ghế chi nhánh 1 = 0
      final outOfStockChair = chairProduct.copyWith(
        branchStocks: {'branch_1': 0, 'branch_2': 12},
      );
      final updatedList = [tableProduct, outOfStockChair, comboProduct];

      final stock = ComboHelper.getAvailableStock(
        product: comboProduct,
        branchId: 'branch_1',
        allProducts: updatedList,
      );

      expect(stock, equals(0));
    });

    test('6. Tính gợi ý giá vốn Combo từ linh kiện thành phần', () {
      // 1 Bàn (700.000đ) + 6 Ghế (200.000đ * 6 = 1.200.000đ) = 1.900.000đ
      final suggestedCost = ComboHelper.calculateSuggestedCostPrice(
        components: comboProduct.comboComponents,
        allProducts: allProducts,
      );

      expect(suggestedCost, equals(1900000.0));
    });

    test('7. Xử lý an toàn khi không tìm thấy ID sản phẩm thành phần', () {
      const invalidCombo = Product(
        id: 'invalid_combo',
        name: 'Combo lỗi',
        code: 'ERR',
        price: 1000,
        costPrice: 500,
        branchStocks: {'branch_1': 0},
        category: 'Khác',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'non_existent_id',
            productCode: 'NONE',
            productName: 'Không tồn tại',
            quantity: 1,
          ),
        ],
      );

      final stock = ComboHelper.getAvailableStock(
        product: invalidCombo,
        branchId: 'branch_1',
        allProducts: allProducts,
      );

      expect(stock, equals(0));
    });

    test('8. Kiểm tra serialization/deserialization cho ComboComponent & ProductModel', () {
      const comp = ComboComponent(
        productId: 'p01',
        productCode: 'P01',
        productName: 'Test Item',
        quantity: 3,
        costPrice: 50000,
      );

      final map = comp.toMap();
      final fromMapComp = ComboComponent.fromMap(map);

      expect(fromMapComp.productId, equals('p01'));
      expect(fromMapComp.productCode, equals('P01'));
      expect(fromMapComp.quantity, equals(3));
      expect(fromMapComp.costPrice, equals(50000.0));

      final productModel = ProductModel(
        id: 'm01',
        name: 'Test Combo',
        code: 'TC01',
        price: 500000,
        costPrice: 300000,
        branchStocks: const {'branch_1': 0},
        category: 'Test',
        isCombo: true,
        comboComponents: const [comp],
      );

      final modelMap = productModel.toMap();
      final parsedModel = ProductModel.fromMap(modelMap);

      expect(parsedModel.isCombo, isTrue);
      expect(parsedModel.comboComponents.length, equals(1));
      expect(parsedModel.comboComponents.first.productName, equals('Test Item'));
    });
  });
}
