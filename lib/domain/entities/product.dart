import 'combo_component.dart';
import 'product_unit.dart';

class Product {
  final String id;
  final String name;
  final String code; // Mã hàng (e.g. XD15)
  final String? barcode; // Mã vạch
  final String? brand;
  final String? model;
  final double price; // Giá bán
  final double costPrice; // Giá vốn
  final Map<String, int>
      branchStocks; // Lượng tồn chi nhánh: {'branch_1': 1, 'branch_2': 0}
  final String category;

  // New fields from Excel
  final String? type;
  final String? category3Levels;
  final String? unit;
  final String? description;
  final String? noteTemplate;
  final String? components;
  final String? imageUrl;

  // Combo fields
  final bool isCombo;
  final List<ComboComponent> comboComponents;

  // Multi-unit & stock thresholds
  final int? minStock; // Định mức tồn tối thiểu
  final int? maxStock; // Định mức tồn tối đa
  final List<ProductUnit> units; // Danh sách đơn vị tính quy đổi

  // Active for Sale switch (true = allow sale, false = disabled/inactive)
  final bool allowSale;

  const Product({
    required this.id,
    required this.name,
    required this.code,
    this.barcode,
    this.brand,
    this.model,
    required this.price,
    required this.costPrice,
    required this.branchStocks,
    required this.category,
    this.type,
    this.category3Levels,
    this.unit,
    this.description,
    this.noteTemplate,
    this.components,
    this.imageUrl,
    this.isCombo = false,
    this.comboComponents = const [],
    this.minStock,
    this.maxStock,
    this.units = const [],
    this.allowSale = true,
  });

  bool get isActive => allowSale;

  // Tính tổng tồn của tất cả chi nhánh
  int get stock => branchStocks.values.fold(0, (sum, val) => sum + val);

  // Helper getters
  bool get isOutOfStock => stock <= 0;
  bool isLowStock([int fallbackMin = 5]) =>
      stock > 0 && stock <= (minStock ?? fallbackMin);
  bool get hasStock => stock > 0;
  int stockInBranch(String branchId) {
    if (branchStocks.isEmpty || branchId.trim().isEmpty) return 0;

    // 1. Exact key match
    if (branchStocks.containsKey(branchId)) {
      return branchStocks[branchId] ?? 0;
    }

    final normalized = branchId.trim().toLowerCase();

    // 2. Canonical store_001 / branch_1 / Đông Thắng (ĐT)
    if (normalized == 'store_001' ||
        normalized == 'branch_1' ||
        normalized == 'đt' ||
        normalized == 'dt' ||
        normalized.contains('đông thắng') ||
        normalized.contains('dong thang')) {
      for (final entry in branchStocks.entries) {
        final k = entry.key.trim().toLowerCase();
        if (k == 'store_001' ||
            k == 'branch_1' ||
            k == 'đt' ||
            k == 'dt' ||
            k.contains('đông thắng') ||
            k.contains('dong thang')) {
          return entry.value;
        }
      }
    }

    // 3. Canonical store_002 / branch_2 / Thới Bình (TB)
    if (normalized == 'store_002' ||
        normalized == 'branch_2' ||
        normalized == 'tb' ||
        normalized.contains('thới bình') ||
        normalized.contains('thoi binh') ||
        normalized.contains('thời bình')) {
      for (final entry in branchStocks.entries) {
        final k = entry.key.trim().toLowerCase();
        if (k == 'store_002' ||
            k == 'branch_2' ||
            k == 'tb' ||
            k.contains('thới bình') ||
            k.contains('thoi binh') ||
            k.contains('thời bình')) {
          return entry.value;
        }
      }
    }

    // 4. Case-insensitive key match
    for (final entry in branchStocks.entries) {
      if (entry.key.trim().toLowerCase() == normalized) {
        return entry.value;
      }
    }

    return 0;
  }

  Product copyWith({
    String? name,
    String? code,
    String? barcode,
    String? brand,
    String? model,
    double? price,
    double? costPrice,
    Map<String, int>? branchStocks,
    String? category,
    String? type,
    String? category3Levels,
    String? unit,
    String? description,
    String? noteTemplate,
    String? components,
    String? imageUrl,
    bool? isCombo,
    List<ComboComponent>? comboComponents,
    int? minStock,
    int? maxStock,
    List<ProductUnit>? units,
    bool? allowSale,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        code: code ?? this.code,
        barcode: barcode ?? this.barcode,
        brand: brand ?? this.brand,
        model: model ?? this.model,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        branchStocks: branchStocks ?? this.branchStocks,
        category: category ?? this.category,
        type: type ?? this.type,
        category3Levels: category3Levels ?? this.category3Levels,
        unit: unit ?? this.unit,
        description: description ?? this.description,
        noteTemplate: noteTemplate ?? this.noteTemplate,
        components: components ?? this.components,
        imageUrl: imageUrl ?? this.imageUrl,
        isCombo: isCombo ?? this.isCombo,
        comboComponents: comboComponents ?? this.comboComponents,
        minStock: minStock ?? this.minStock,
        maxStock: maxStock ?? this.maxStock,
        units: units ?? this.units,
        allowSale: allowSale ?? this.allowSale,
      );
}

