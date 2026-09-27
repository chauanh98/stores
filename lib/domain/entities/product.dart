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
  final List<String> images;

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
    this.images = const [],
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
  /// Trích xuất danh sách tất cả các URL ảnh từ chuỗi đầu vào.
  /// Hỗ trợ cả Network URL (HTTP/HTTPS/GS) và Base64 Data URL (`data:image/...`),
  /// đảm bảo không bị cắt đứt dấu phẩy phân tách bên trong Data URL.
  static List<String> parseImageUrls(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    final trimmed = raw.trim();

    if (!trimmed.contains(',')) {
      if (trimmed.startsWith('http://') ||
          trimmed.startsWith('https://') ||
          trimmed.startsWith('gs://') ||
          (trimmed.startsWith('data:image') && trimmed.contains('base64,'))) {
        return [trimmed];
      }
      return const [];
    }

    if (trimmed.startsWith('data:image') &&
        trimmed.contains('base64,') &&
        !trimmed.contains(',http://') &&
        !trimmed.contains(',https://') &&
        !trimmed.contains(',gs://') &&
        !trimmed.contains(',data:image') &&
        !trimmed.contains(', http://') &&
        !trimmed.contains(', https://') &&
        !trimmed.contains(', gs://') &&
        !trimmed.contains(', data:image')) {
      return [trimmed];
    }

    final parts = trimmed.split(',');
    final List<String> result = [];
    final buffer = StringBuffer();

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (buffer.isEmpty) {
        buffer.write(part);
      } else {
        final nextTrimmed = part.trim();
        final isNewBoundary = nextTrimmed.startsWith('http://') ||
            nextTrimmed.startsWith('https://') ||
            nextTrimmed.startsWith('gs://') ||
            nextTrimmed.startsWith('data:image');

        if (isNewBoundary) {
          final finished = buffer.toString().trim();
          if (finished.isNotEmpty) {
            result.add(finished);
          }
          buffer.clear();
          buffer.write(part);
        } else {
          buffer.write(',');
          buffer.write(part);
        }
      }
    }

    final finished = buffer.toString().trim();
    if (finished.isNotEmpty) {
      result.add(finished);
    }

    return result
        .map((u) => u.trim())
        .where((u) =>
            u.startsWith('http://') ||
            u.startsWith('https://') ||
            u.startsWith('gs://') ||
            (u.startsWith('data:image') && u.contains('base64,')))
        .toList();
  }

  /// Danh sách tất cả link ảnh hợp lệ (ưu tiên mảng images, hoặc tách chuỗi imageUrl chứa nhiều ảnh)
  List<String> get allImageUrls {
    if (images.isNotEmpty) return images;
    return parseImageUrls(imageUrl);
  }

  /// Link ảnh chính (ảnh đầu tiên nếu có nhiều ảnh)
  String? get primaryImageUrl =>
      allImageUrls.isNotEmpty ? allImageUrls.first : null;

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
    List<String>? images,
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
        images: images ?? this.images,
        isCombo: isCombo ?? this.isCombo,
        comboComponents: comboComponents ?? this.comboComponents,
        minStock: minStock ?? this.minStock,
        maxStock: maxStock ?? this.maxStock,
        units: units ?? this.units,
        allowSale: allowSale ?? this.allowSale,
      );
}
