import 'package:stores/domain/entities/combo_component.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/product_unit.dart';

/// Test fixtures and mock generators for Product and ProductUnit domain entities
class MockProductData {
  /// Factory helper to create a [ProductUnit]
  static ProductUnit createProductUnit({
    String id = 'unit_001',
    String unitName = 'Lon',
    int conversionRate = 1,
    double price = 15000.0,
    double? costPrice = 11000.0,
    String? barcode = '893000000001',
    String? code = 'BSG-LON',
    bool isDirectSale = true,
  }) {
    return ProductUnit(
      id: id,
      unitName: unitName,
      conversionRate: conversionRate,
      price: price,
      costPrice: costPrice,
      barcode: barcode,
      code: code,
      isDirectSale: isDirectSale,
    );
  }

  /// Factory helper to create standard multi-unit hierarchy for a beverage
  static List<ProductUnit> sampleBeverageUnits() {
    return [
      createProductUnit(
        id: 'u_lon',
        unitName: 'Lon',
        conversionRate: 1,
        price: 15000.0,
        costPrice: 11000.0,
        barcode: '893111111001',
        code: 'BSG-LON',
        isDirectSale: true,
      ),
      createProductUnit(
        id: 'u_loc',
        unitName: 'Lốc (6 lon)',
        conversionRate: 6,
        price: 88000.0,
        costPrice: 65000.0,
        barcode: '893111111006',
        code: 'BSG-LOC6',
        isDirectSale: true,
      ),
      createProductUnit(
        id: 'u_thung',
        unitName: 'Thùng (24 lon)',
        conversionRate: 24,
        price: 345000.0,
        costPrice: 260000.0,
        barcode: '893111111024',
        code: 'BSG-THUNG24',
        isDirectSale: true,
      ),
    ];
  }

  /// Factory helper to create a [Product] entity with multi-unit and stock threshold support
  static Product createProduct({
    String id = 'prod_001',
    String name = 'Bia Saigon Special',
    String code = 'BSG01',
    String? barcode = '893111111001',
    String? brand = 'Sabeco',
    String? model,
    double price = 15000.0,
    double costPrice = 11000.0,
    Map<String, int> branchStocks = const {'branch_1': 50, 'branch_2': 30},
    String category = 'Đồ uống',
    String? type = 'Hàng hóa',
    String? category3Levels,
    String? unit = 'Lon',
    String? description = 'Bia lon Saigon Special 330ml',
    String? noteTemplate,
    String? components,
    String? imageUrl,
    bool isCombo = false,
    List<ComboComponent> comboComponents = const [],
    int? minStock = 10,
    int? maxStock = 200,
    List<ProductUnit> units = const [],
  }) {
    return Product(
      id: id,
      name: name,
      code: code,
      barcode: barcode,
      brand: brand,
      model: model,
      price: price,
      costPrice: costPrice,
      branchStocks: branchStocks,
      category: category,
      type: type,
      category3Levels: category3Levels,
      unit: unit,
      description: description,
      noteTemplate: noteTemplate,
      components: components,
      imageUrl: imageUrl,
      isCombo: isCombo,
      comboComponents: comboComponents,
      minStock: minStock,
      maxStock: maxStock,
      units: units,
    );
  }

  /// Predefined product catalog with diverse stock thresholds and units
  static List<Product> sampleProductCatalog() {
    return [
      // 1. Normal stock with multi-units
      createProduct(
        id: 'p_beverage_1',
        name: 'Bia Saigon Special 330ml',
        code: 'BSG01',
        barcode: '893111111001',
        brand: 'Sabeco',
        price: 15000.0,
        costPrice: 11000.0,
        branchStocks: {'branch_1': 60, 'branch_2': 40}, // Total: 100
        category: 'Đồ uống',
        minStock: 20,
        maxStock: 300,
        units: sampleBeverageUnits(),
      ),
      // 2. Low stock (stock <= minStock)
      createProduct(
        id: 'p_tech_low',
        name: 'Cáp sạc Type-C Anker 60W',
        code: 'ANK-CC01',
        barcode: '893222222001',
        brand: 'Anker',
        price: 180000.0,
        costPrice: 100000.0,
        branchStocks: {'branch_1': 3, 'branch_2': 1}, // Total: 4 <= minStock (5)
        category: 'Phụ kiện điện thoại',
        minStock: 5,
        maxStock: 50,
      ),
      // 3. Out of stock (stock = 0)
      createProduct(
        id: 'p_snack_out',
        name: 'Bánh que Pocky Socola',
        code: 'PK-SOC01',
        barcode: '893333333001',
        brand: 'Glico',
        price: 12000.0,
        costPrice: 8000.0,
        branchStocks: {'branch_1': 0, 'branch_2': 0}, // Total: 0
        category: 'Bánh kẹo',
        minStock: 10,
        maxStock: 100,
      ),
      // 4. Over max stock (stock > maxStock)
      createProduct(
        id: 'p_home_over',
        name: 'Khăn giấy lụa Paseo 3 lớp',
        code: 'PS-KG01',
        barcode: '893444444001',
        brand: 'Paseo',
        price: 25000.0,
        costPrice: 16000.0,
        branchStocks: {'branch_1': 150, 'branch_2': 100}, // Total: 250 > maxStock (200)
        category: 'Gia dụng',
        minStock: 20,
        maxStock: 200,
      ),
      // 5. Combo product
      createProduct(
        id: 'p_combo_snack',
        name: 'Combo Tiệc Nhẹ (Bia + Bánh)',
        code: 'CB-PARTY01',
        price: 80000.0,
        costPrice: 55000.0,
        branchStocks: {'branch_1': 10, 'branch_2': 5},
        category: 'Combo',
        isCombo: true,
        comboComponents: const [
          ComboComponent(
            productId: 'p_beverage_1',
            productCode: 'BSG01',
            productName: 'Bia Saigon Special 330ml',
            quantity: 4,
            costPrice: 11000.0,
          ),
          ComboComponent(
            productId: 'p_snack_out',
            productCode: 'PK-SOC01',
            productName: 'Bánh que Pocky Socola',
            quantity: 2,
            costPrice: 8000.0,
          ),
        ],
      ),
    ];
  }
}
