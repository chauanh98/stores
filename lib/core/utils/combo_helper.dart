import '../../domain/entities/combo_component.dart';
import '../../domain/entities/product.dart';

class ComboHelper {
  /// Tính tồn kho khả dụng của sản phẩm tại một chi nhánh cụ thể.
  /// Nếu là sản phẩm thường: lấy trực tiếp từ `branchStocks[branchId]`.
  /// Nếu là sản phẩm Combo: tính theo số lượng nhỏ nhất có thể lắp ráp từ các linh kiện thành phần.
  static int getAvailableStock({
    required Product product,
    required String branchId,
    required List<Product> allProducts,
  }) {
    if (!product.isCombo || product.comboComponents.isEmpty) {
      return product.branchStocks[branchId] ?? 0;
    }

    int maxCombos = 9999999;
    final Map<String, Product> productMap = {
      for (final p in allProducts) p.id: p
    };

    for (final comp in product.comboComponents) {
      final child = productMap[comp.productId];
      if (child == null) {
        return 0; // Linh kiện không tồn tại
      }
      if (comp.quantity <= 0) continue;

      // Tồn kho linh kiện tại chi nhánh
      final childStock = child.branchStocks[branchId] ?? 0;
      final possible = childStock ~/ comp.quantity;

      if (possible < maxCombos) {
        maxCombos = possible;
      }
    }

    return maxCombos == 9999999 || maxCombos < 0 ? 0 : maxCombos;
  }

  /// Tính tổng tồn kho khả dụng của Combo ở tất cả các chi nhánh
  static int getTotalAvailableStock({
    required Product product,
    required List<Product> allProducts,
    List<String> branchIds = const ['branch_1', 'branch_2'],
  }) {
    if (!product.isCombo) {
      return product.stock;
    }

    int total = 0;
    for (final bId in branchIds) {
      total += getAvailableStock(
        product: product,
        branchId: bId,
        allProducts: allProducts,
      );
    }
    return total;
  }

  /// Tính gợi ý giá vốn Combo dựa trên tổng (giá vốn linh kiện * số lượng)
  static double calculateSuggestedCostPrice({
    required List<ComboComponent> components,
    required List<Product> allProducts,
  }) {
    final Map<String, Product> productMap = {
      for (final p in allProducts) p.id: p
    };

    double totalCost = 0.0;
    for (final comp in components) {
      final child = productMap[comp.productId];
      if (child != null) {
        totalCost += (child.costPrice) * comp.quantity;
      } else if (comp.costPrice != null) {
        totalCost += comp.costPrice! * comp.quantity;
      }
    }
    return totalCost;
  }
}
