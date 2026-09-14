import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/combo_helper.dart';
import 'package:stores/data/models/product_model.dart';
import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';

void main() {
  group('Requirement R1: Branch Stocks Dynamic Mapping & Dual-Key Resolution', () {
    test('Product.stockInBranch seamlessly resolves canonical store IDs, branch aliases, and store names', () {
      // Product with canonical store keys
      const productCanonical = Product(
        id: 'p_canon',
        name: 'Cà phê sữa đá Highlands',
        code: 'CF01',
        price: 29000,
        costPrice: 18000,
        branchStocks: {
          'store_001': 24, // Đông Thắng (ĐT)
          'store_002': 16, // Thới Bình (TB)
          'store_003': 10, // Cần Thơ (CT)
        },
        category: 'Đồ uống',
      );

      // Querying with canonical IDs
      expect(productCanonical.stockInBranch('store_001'), equals(24));
      expect(productCanonical.stockInBranch('store_002'), equals(16));
      expect(productCanonical.stockInBranch('store_003'), equals(10));

      // Querying with legacy branch aliases
      expect(productCanonical.stockInBranch('branch_1'), equals(24));
      expect(productCanonical.stockInBranch('branch_2'), equals(16));

      // Querying with Vietnamese store names
      expect(productCanonical.stockInBranch('Chi nhánh Đông Thắng'), equals(24));
      expect(productCanonical.stockInBranch('Chi nhánh Thới Bình'), equals(16));
      expect(productCanonical.stockInBranch('Chi nhánh Thời Bình'), equals(16));

      // Querying with short code acronyms
      expect(productCanonical.stockInBranch('ĐT'), equals(24));
      expect(productCanonical.stockInBranch('TB'), equals(16));

      // Non-existent branch returns 0
      expect(productCanonical.stockInBranch('store_999'), equals(0));
      expect(productCanonical.stockInBranch(''), equals(0));
    });

    test('Product with legacy branch_1 / branch_2 keys resolves when queried with canonical IDs', () {
      const productLegacy = Product(
        id: 'p_legacy',
        name: 'Trà xanh không độ',
        code: 'TX01',
        price: 10000,
        costPrice: 6500,
        branchStocks: {
          'branch_1': 50, // Đông Thắng
          'branch_2': 35, // Thới Bình
        },
        category: 'Đồ uống',
      );

      expect(productLegacy.stockInBranch('store_001'), equals(50));
      expect(productLegacy.stockInBranch('store_002'), equals(35));
      expect(productLegacy.stockInBranch('branch_1'), equals(50));
      expect(productLegacy.stockInBranch('branch_2'), equals(35));
      expect(productLegacy.stockInBranch('ĐT'), equals(50));
      expect(productLegacy.stockInBranch('TB'), equals(35));
    });

    test('Product.stock correctly sums across all branches regardless of key format', () {
      const productMixed = Product(
        id: 'p_mix',
        name: 'Mì Hảo Hảo Tôm Chua Cay',
        code: 'HH01',
        price: 4500,
        costPrice: 3200,
        branchStocks: {
          'store_001': 100,
          'store_002': 50,
          'store_003': 30,
        },
        category: 'Thực phẩm',
      );

      expect(productMixed.stock, equals(180));
    });

    test('ProductModel parses and maintains multi-branch stock map without collapsing to single branch', () {
      final jsonMap = {
        'id': 'p_multi',
        'name': 'Bánh Chocopie Lotte',
        'code': 'CP01',
        'price': 48000.0,
        'costPrice': 35000.0,
        'branchStocks': {
          'store_001': 40,
          'store_002': 25,
          'store_003': 15,
        },
        'category': 'Bánh kẹo',
      };

      final model = ProductModel.fromMap(jsonMap);
      expect(model.branchStocks.length, equals(3));
      expect(model.branchStocks['store_001'], equals(40));
      expect(model.branchStocks['store_002'], equals(25));
      expect(model.branchStocks['store_003'], equals(15));

      final serialized = model.toMap();
      expect(serialized['branchStocks']['store_001'], equals(40));
      expect(serialized['branchStocks']['store_002'], equals(25));
      expect(serialized['branchStocks']['store_003'], equals(15));
    });

    test('ComboHelper calculates combo availability for canonical and legacy branch IDs accurately', () {
      const component1 = Product(
        id: 'comp_coke',
        name: 'Coca Cola 330ml',
        code: 'COKE01',
        price: 10000,
        costPrice: 7000,
        branchStocks: {'store_001': 20, 'store_002': 10},
        category: 'Đồ uống',
      );

      const component2 = Product(
        id: 'comp_snack',
        name: 'Snack Lay Oishi',
        code: 'LAY01',
        price: 12000,
        costPrice: 8000,
        branchStocks: {'store_001': 15, 'store_002': 30},
        category: 'Đồ ăn vặt',
      );

      const comboProduct = Product(
        id: 'combo_party',
        name: 'Combo Party Vui Vẻ',
        code: 'CB_PARTY',
        price: 20000,
        costPrice: 15000,
        branchStocks: {'store_001': 0, 'store_002': 0},
        category: 'Combo',
        isCombo: true,
        comboComponents: [
          ComboComponent(
            productId: 'comp_coke',
            productCode: 'COKE01',
            productName: 'Coca Cola 330ml',
            quantity: 2,
            costPrice: 7000,
          ),
          ComboComponent(
            productId: 'comp_snack',
            productCode: 'LAY01',
            productName: 'Snack Lay Oishi',
            quantity: 1,
            costPrice: 8000,
          ),
        ],
      );

      final allProducts = [component1, component2, comboProduct];

      // At store_001: Coke has 20 (enough for 10 combos), Lay has 15 (enough for 15 combos) -> available = 10
      final stockAtStore1 = ComboHelper.getAvailableStock(
        product: comboProduct,
        branchId: 'store_001',
        allProducts: allProducts,
      );
      expect(stockAtStore1, equals(10));

      // At store_002: Coke has 10 (enough for 5 combos), Lay has 30 (enough for 30 combos) -> available = 5
      final stockAtStore2 = ComboHelper.getAvailableStock(
        product: comboProduct,
        branchId: 'store_002',
        allProducts: allProducts,
      );
      expect(stockAtStore2, equals(5));

      // Querying via legacy alias branch_1 (maps to store_001) -> 10
      final stockViaBranch1 = ComboHelper.getAvailableStock(
        product: comboProduct,
        branchId: 'branch_1',
        allProducts: allProducts,
      );
      expect(stockViaBranch1, equals(10));

      // Querying via legacy alias branch_2 (maps to store_002) -> 5
      final stockViaBranch2 = ComboHelper.getAvailableStock(
        product: comboProduct,
        branchId: 'branch_2',
        allProducts: allProducts,
      );
      expect(stockViaBranch2, equals(5));

      // Total available combo stock across network: 10 + 5 = 15
      final totalComboStock = ComboHelper.getTotalAvailableStock(
        product: comboProduct,
        allProducts: allProducts,
        branchIds: ['store_001', 'store_002'],
      );
      expect(totalComboStock, equals(15));
    });
  });
}
