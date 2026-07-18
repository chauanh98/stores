import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/entities/order_item.dart';
import '../../../domain/entities/product.dart';

// Provider quản lý chi nhánh đang được chọn để bán hàng tại POS
final selectedPOSBranchProvider = StateProvider<String>((ref) => 'branch_1');

// Model đại diện cho một sản phẩm trong giỏ hàng
class CartItem {
  final Product product;
  final int quantity;
  final double? customPrice; // Giá bán tùy chỉnh cho Admin

  const CartItem({
    required this.product,
    required this.quantity,
    this.customPrice,
  });

  CartItem copyWith({int? quantity, double? customPrice}) {
    return CartItem(
      product: product,
      quantity: quantity ?? this.quantity,
      customPrice: customPrice ?? this.customPrice,
    );
  }

  double get price => customPrice ?? product.price;

  double get total => price * quantity;
}

// Notifier quản lý danh sách sản phẩm trong giỏ
class CartNotifier extends StateNotifier<Map<String, CartItem>> {
  CartNotifier() : super({});

  void addToCart(Product product) {
    if (state.containsKey(product.id)) {
      final currentItem = state[product.id]!;
      state = {
        ...state,
        product.id: currentItem.copyWith(quantity: currentItem.quantity + 1),
      };
    } else {
      state = {
        ...state,
        product.id: CartItem(product: product, quantity: 1),
      };
    }
  }

  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeFromCart(productId);
      return;
    }
    if (state.containsKey(productId)) {
      final currentItem = state[productId]!;
      state = {
        ...state,
        productId: currentItem.copyWith(quantity: quantity),
      };
    }
  }

  void updatePrice(String productId, double price) {
    if (state.containsKey(productId)) {
      final currentItem = state[productId]!;
      state = {
        ...state,
        productId: currentItem.copyWith(customPrice: price),
      };
    }
  }

  void increaseQuantity(String productId) {
    if (state.containsKey(productId)) {
      final currentItem = state[productId]!;
      state = {
        ...state,
        productId: currentItem.copyWith(quantity: currentItem.quantity + 1),
      };
    }
  }

  void decreaseQuantity(String productId) {
    if (state.containsKey(productId)) {
      final currentItem = state[productId]!;
      if (currentItem.quantity <= 1) {
        removeFromCart(productId);
      } else {
        state = {
          ...state,
          productId: currentItem.copyWith(quantity: currentItem.quantity - 1),
        };
      }
    }
  }

  void removeFromCart(String productId) {
    final updated = Map<String, CartItem>.from(state);
    updated.remove(productId);
    state = updated;
  }

  void clearCart() {
    state = {};
  }

  void populateCart(List<OrderItem> items, List<Product> allProducts) {
    final newCart = <String, CartItem>{};
    for (final item in items) {
      final product = allProducts.firstWhere((p) => p.id == item.productId,
          orElse: () => Product(
                id: item.productId,
                name: item.productName,
                code: '',
                brand: '',
                model: '',
                price: item.price,
                costPrice: 0.0,
                branchStocks: const {},
                category: '',
              ));
      newCart[item.productId] = CartItem(
        product: product,
        quantity: item.quantity,
        customPrice: item.price != product.price ? item.price : null,
      );
    }
    state = newCart;
  }
}

// Provider chính của giỏ hàng
final cartProvider =
    StateNotifierProvider<CartNotifier, Map<String, CartItem>>((ref) {
  return CartNotifier();
});

// Provider tính tổng số lượng sản phẩm trong giỏ
final cartTotalItemsProvider = Provider<int>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.values.fold(0, (sum, item) => sum + item.quantity);
});

// Provider tính tổng số tiền hàng
final cartTotalAmountProvider = Provider<double>((ref) {
  final cart = ref.watch(cartProvider);
  return cart.values.fold(0.0, (sum, item) => sum + item.total);
});

// Provider quản lý mã đơn lưu tạm đang hoạt động
final activeOrderIdProvider = StateProvider<String?>((ref) => null);
