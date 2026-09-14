import '../../domain/entities/combo_component.dart';
import '../../domain/entities/product.dart';
import '../../domain/entities/product_unit.dart';

class ProductModel {
  final String id;
  final String name;
  final String code;
  final String? barcode;
  final String? brand;
  final String? model;
  final double price;
  final double costPrice;
  final Map<String, int> branchStocks;
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
  final int? minStock;
  final int? maxStock;
  final List<ProductUnit> units;

  // Active for Sale
  final bool allowSale;

  int get stock => branchStocks.values.fold(0, (sum, val) => sum + val);

  int stockInBranch(String branchId) => toEntity().stockInBranch(branchId);

  Product toEntity() => Product(
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
        allowSale: allowSale,
      );

  factory ProductModel.fromEntity(Product product) => ProductModel(
        id: product.id,
        name: product.name,
        code: product.code,
        barcode: product.barcode,
        brand: product.brand,
        model: product.model,
        price: product.price,
        costPrice: product.costPrice,
        branchStocks: product.branchStocks,
        category: product.category,
        type: product.type,
        category3Levels: product.category3Levels,
        unit: product.unit,
        description: product.description,
        noteTemplate: product.noteTemplate,
        components: product.components,
        imageUrl: product.imageUrl,
        isCombo: product.isCombo,
        comboComponents: product.comboComponents,
        minStock: product.minStock,
        maxStock: product.maxStock,
        units: product.units,
        allowSale: product.allowSale,
      );

  const ProductModel({
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'code': code,
        'barcode': barcode,
        'brand': brand,
        'model': model,
        'price': price,
        'costPrice': costPrice,
        'branchStocks': branchStocks,
        'category': category,
        'type': type,
        'category3Levels': category3Levels,
        'unit': unit,
        'description': description,
        'noteTemplate': noteTemplate,
        'components': components,
        'imageUrl': imageUrl,
        'isCombo': isCombo,
        'comboComponents': comboComponents.map((c) => c.toMap()).toList(),
        'minStock': minStock,
        'maxStock': maxStock,
        'units': units.map((u) => u.toMap()).toList(),
        'allowSale': allowSale,
      };

  factory ProductModel.fromMap(Map<dynamic, dynamic> map,
      [String? sourceStoreId]) {
    // Normalization & Fallback cho branchStocks
    final Map<String, int> resolvedStocks = {};

    final isSourceStore002 = sourceStoreId != null &&
        (sourceStoreId.trim().toLowerCase() == 'store_002' ||
            sourceStoreId.trim().toLowerCase() == 'branch_2' ||
            sourceStoreId.trim().toLowerCase() == 'tb' ||
            sourceStoreId.toLowerCase().contains('thới bình') ||
            sourceStoreId.toLowerCase().contains('thoi binh') ||
            sourceStoreId.toLowerCase().contains('thời bình'));

    final dynamic rawStocks = map['branchStocks'] ?? map['stocks'];
    if (rawStocks != null && rawStocks is Map) {
      if (rawStocks.isNotEmpty) {
        int? store001Qty;
        int? legacyBranch1Qty;
        int? store002Qty;
        int? legacyBranch2Qty;
        final Map<String, int> otherStores = {};

        for (final entry in rawStocks.entries) {
          final k = entry.key?.toString().trim() ?? '';
          if (k.isEmpty) continue;
          final v = entry.value;
          final qty =
              v is num ? v.toInt() : (int.tryParse(v?.toString() ?? '0') ?? 0);

          final lower = k.toLowerCase();
          if (lower == 'store_001') {
            store001Qty = qty;
          } else if (lower == 'store_002') {
            store002Qty = qty;
          } else if (lower == 'branch_1') {
            legacyBranch1Qty = qty;
          } else if (lower == 'branch_2') {
            legacyBranch2Qty = qty;
          } else if (lower == 'đt' ||
              lower == 'dt' ||
              lower.contains('đông thắng') ||
              lower.contains('dong thang')) {
            store001Qty ??= qty;
          } else if (lower == 'tb' ||
              lower.contains('thới bình') ||
              lower.contains('thoi binh') ||
              lower.contains('thời bình')) {
            store002Qty ??= qty;
          } else {
            otherStores[k] = qty;
          }
        }

        if (isSourceStore002) {
          // When sourceStoreId == 'store_002' (Thới Bình):
          // branch_1 is local (store_002), branch_2 is remote (store_001)
          if (store001Qty != null || legacyBranch2Qty != null) {
            resolvedStocks['store_001'] = store001Qty ?? legacyBranch2Qty!;
          }
          if (store002Qty != null || legacyBranch1Qty != null) {
            resolvedStocks['store_002'] = store002Qty ?? legacyBranch1Qty!;
          }
        } else {
          // Default / store_001 (Đông Thắng):
          // branch_1 is local (store_001), branch_2 is remote (store_002)
          if (store001Qty != null || legacyBranch1Qty != null) {
            resolvedStocks['store_001'] = store001Qty ?? legacyBranch1Qty!;
          }
          if (store002Qty != null || legacyBranch2Qty != null) {
            resolvedStocks['store_002'] = store002Qty ?? legacyBranch2Qty!;
          }
        }
        resolvedStocks.addAll(otherStores);
      }
    } else {
      final oldStock = (map['stock'] as num? ?? 0).toInt();
      if (isSourceStore002) {
        resolvedStocks['store_001'] = 0;
        resolvedStocks['store_002'] = oldStock;
      } else {
        resolvedStocks['store_001'] = oldStock;
        resolvedStocks['store_002'] = 0;
      }
    }

    // Fallback cho giá vốn nếu bản ghi cũ chưa có
    final double resolvedCostPrice = map['costPrice'] != null
        ? (map['costPrice'] as num).toDouble()
        : ((map['price'] as num? ?? 0).toDouble() * 0.7);

    // Read comboComponents
    List<ComboComponent> comboComps = [];
    if (map['comboComponents'] != null && map['comboComponents'] is List) {
      comboComps = (map['comboComponents'] as List)
          .whereType<Map>()
          .map((item) => ComboComponent.fromMap(item))
          .toList();
    }

    // Read units
    List<ProductUnit> resolvedUnits = [];
    if (map['units'] != null) {
      if (map['units'] is List) {
        resolvedUnits = (map['units'] as List)
            .whereType<Map>()
            .map((item) => ProductUnit.fromMap(item))
            .toList();
      } else if (map['units'] is Map) {
        resolvedUnits = (map['units'] as Map)
            .values
            .whereType<Map>()
            .map((item) => ProductUnit.fromMap(item))
            .toList();
      }
    }

    // Fallback cho allowSale (hỗ trợ cả isActive nếu migrate từ DB cũ)
    final bool resolvedAllowSale = map['allowSale'] != null
        ? (map['allowSale'] as bool)
        : (map['isActive'] != null ? (map['isActive'] as bool) : true);

    return ProductModel(
      id: map['id'] as String? ?? '',
      name: map['name'] as String? ?? '',
      code: map['code'] as String? ?? (map['id'] as String? ?? ''),
      barcode: map['barcode'] as String?,
      brand: map['brand'] as String?,
      model: map['model'] as String?,
      price: (map['price'] as num? ?? 0).toDouble(),
      costPrice: resolvedCostPrice,
      branchStocks: resolvedStocks,
      category: map['category'] as String? ?? 'Khác',
      type: map['type'] as String?,
      category3Levels: map['category3Levels'] as String?,
      unit: map['unit'] as String?,
      description: map['description'] as String?,
      noteTemplate: map['noteTemplate'] as String?,
      components: map['components'] as String?,
      imageUrl: map['imageUrl'] as String?,
      isCombo: map['isCombo'] as bool? ?? false,
      comboComponents: comboComps,
      minStock: map['minStock'] != null
          ? (map['minStock'] as num).toInt()
          : null,
      maxStock: map['maxStock'] != null
          ? (map['maxStock'] as num).toInt()
          : null,
      units: resolvedUnits,
      allowSale: resolvedAllowSale,
    );
  }
}

