import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/filter_storage_service.dart';
import '../../../core/utils/store_resolver_helper.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order_item.dart';
import '../../../domain/entities/product.dart';
import '../auth/auth_providers.dart';

// Provider quản lý chi nhánh đang được chọn để bán hàng tại POS
final selectedPOSBranchProvider = StateProvider<String>((ref) {
  final user = ref.watch(authProvider);
  if (user != null &&
      (user.isAdmin || user.isSupervisor || user.canSwitchStore)) {
    final selectedStore = ref.watch(selectedStoreIdProvider);
    if (selectedStore != null &&
        selectedStore.isNotEmpty &&
        selectedStore != 'all') {
      return selectedStore;
    }
    try {
      final storage = ref.watch(filterStorageServiceProvider);
      final saved = storage.loadSelectedStoreSync(user.username);
      if (saved != null && saved.isNotEmpty && saved != 'all') {
        return saved;
      }
    } catch (_) {}
  }
  return ref.watch(currentStoreIdProvider);
});

// Provider phân giải tên hiển thị của chi nhánh đang chọn tại POS
final posBranchNameProvider = Provider<String>((ref) {
  final branchId = ref.watch(selectedPOSBranchProvider);
  final availableStoresAsync = ref.watch(availableStoresProvider);
  final storeNames = availableStoresAsync.valueOrNull;
  return StoreResolverHelper.resolveStoreName(branchId, storeNames: storeNames);
});

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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartItem &&
          runtimeType == other.runtimeType &&
          product == other.product &&
          quantity == other.quantity &&
          customPrice == other.customPrice;

  @override
  int get hashCode => Object.hash(product, quantity, customPrice);
}

/// Model đại diện cho 1 tab đơn hàng / hóa đơn tạm trong phiên bán hàng
class CartTab {
  final String id;
  final String title;
  final Map<String, CartItem> items;
  final Customer? customer;
  final double discount;
  final bool isDiscountPercent;
  final String note;
  final String? activeOrderId;
  final DateTime createdAt;

  const CartTab({
    required this.id,
    required this.title,
    this.items = const {},
    this.customer,
    this.discount = 0.0,
    this.isDiscountPercent = false,
    this.note = '',
    this.activeOrderId,
    required this.createdAt,
  });

  int get totalItems =>
      items.values.fold(0, (sum, item) => sum + item.quantity);

  double get totalAmount =>
      items.values.fold(0.0, (sum, item) => sum + item.total);

  CartTab copyWith({
    String? id,
    String? title,
    Map<String, CartItem>? items,
    Customer? customer,
    bool clearCustomer = false,
    double? discount,
    bool? isDiscountPercent,
    String? note,
    String? activeOrderId,
    bool clearActiveOrderId = false,
    DateTime? createdAt,
  }) {
    return CartTab(
      id: id ?? this.id,
      title: title ?? this.title,
      items: items ?? this.items,
      customer: clearCustomer ? null : (customer ?? this.customer),
      discount: discount ?? this.discount,
      isDiscountPercent: isDiscountPercent ?? this.isDiscountPercent,
      note: note ?? this.note,
      activeOrderId:
          clearActiveOrderId ? null : (activeOrderId ?? this.activeOrderId),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CartTab &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          title == other.title &&
          items == other.items &&
          customer == other.customer &&
          discount == other.discount &&
          isDiscountPercent == other.isDiscountPercent &&
          note == other.note &&
          activeOrderId == other.activeOrderId;

  @override
  int get hashCode => Object.hash(
        id,
        title,
        items,
        customer,
        discount,
        isDiscountPercent,
        note,
        activeOrderId,
      );
}

/// State quản lý danh sách các tab giỏ hàng và tab đang hoạt động
class MultiCartState {
  final List<CartTab> tabs;
  final String activeTabId;

  const MultiCartState({
    required this.tabs,
    required this.activeTabId,
  });

  CartTab get activeTab {
    return tabs.firstWhere(
      (tab) => tab.id == activeTabId,
      orElse: () => tabs.isNotEmpty
          ? tabs.first
          : CartTab(
              id: 'cart_1',
              title: 'Hóa đơn 1',
              createdAt: DateTime.now(),
            ),
    );
  }

  int get activeTabIndex {
    final index = tabs.indexWhere((t) => t.id == activeTabId);
    return index >= 0 ? index : 0;
  }

  MultiCartState copyWith({
    List<CartTab>? tabs,
    String? activeTabId,
  }) {
    return MultiCartState(
      tabs: tabs ?? this.tabs,
      activeTabId: activeTabId ?? this.activeTabId,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MultiCartState &&
          runtimeType == other.runtimeType &&
          tabs == other.tabs &&
          activeTabId == other.activeTabId;

  @override
  int get hashCode => Object.hash(tabs, activeTabId);
}

/// Notifier quản lý nghiệp vụ Đa giỏ hàng (Multi-Cart POS)
class MultiCartNotifier extends StateNotifier<MultiCartState> {
  static final Map<String, MultiCartState> _staticFallbackCache = {};

  final String currentBranchId;
  final void Function(MultiCartState state)? onStateChanged;

  MultiCartNotifier({
    this.currentBranchId = 'store_001',
    MultiCartState? initialState,
    this.onStateChanged,
  }) : super(
          initialState ?? _loadBranchState(currentBranchId),
        ) {
    if (initialState != null) {
      if (onStateChanged != null) {
        onStateChanged!(initialState);
      } else {
        _staticFallbackCache[currentBranchId] = initialState;
      }
    }
  }

  static void resetBranchCartsCache() {
    _staticFallbackCache.clear();
  }

  static MultiCartState createInitialState(String branchId) {
    final defaultTab = CartTab(
      id: 'cart_${branchId}_1',
      title: 'Hóa đơn 1',
      createdAt: DateTime.now(),
    );
    return MultiCartState(
      tabs: [defaultTab],
      activeTabId: defaultTab.id,
    );
  }

  static MultiCartState _loadBranchState(String branchId) {
    if (_staticFallbackCache.containsKey(branchId)) {
      return _staticFallbackCache[branchId]!;
    }
    final initial = createInitialState(branchId);
    _staticFallbackCache[branchId] = initial;
    return initial;
  }

  void _syncCache() {
    if (onStateChanged != null) {
      onStateChanged!(state);
    } else {
      _staticFallbackCache[currentBranchId] = state;
    }
  }

  @override
  set state(MultiCartState value) {
    super.state = value;
    _syncCache();
  }

  /// Thêm tab hóa đơn tạm mới và tự động active tab đó
  String addNewTab({String? title}) {
    final tabNumber = _nextTabNumber();
    final newId = 'cart_${DateTime.now().millisecondsSinceEpoch}_$tabNumber';
    final newTitle = title ?? 'Hóa đơn $tabNumber';
    final newTab = CartTab(
      id: newId,
      title: newTitle,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      tabs: [...state.tabs, newTab],
      activeTabId: newId,
    );
    return newId;
  }

  int _nextTabNumber() {
    final regex = RegExp(r'Hóa đơn (\d+)');
    int maxNum = 0;
    for (final tab in state.tabs) {
      final match = regex.firstMatch(tab.title);
      if (match != null) {
        final num = int.tryParse(match.group(1)!) ?? 0;
        if (num > maxNum) maxNum = num;
      }
    }
    return maxNum + 1;
  }

  /// Chuyển tab giỏ hàng đang active
  void switchTab(String tabId) {
    if (state.tabs.any((t) => t.id == tabId)) {
      state = state.copyWith(activeTabId: tabId);
    }
  }

  /// Đóng tab giỏ hàng. Nếu đóng tab duy nhất hoặc tab đang active, tự động xử lý an toàn
  void closeTab(String tabId) {
    final currentIndex = state.tabs.indexWhere((t) => t.id == tabId);
    if (currentIndex == -1) return;

    final updatedTabs = state.tabs.where((t) => t.id != tabId).toList();

    if (updatedTabs.isEmpty) {
      final defaultTab = CartTab(
        id: 'cart_${DateTime.now().millisecondsSinceEpoch}',
        title: 'Hóa đơn 1',
        createdAt: DateTime.now(),
      );
      state = MultiCartState(
        tabs: [defaultTab],
        activeTabId: defaultTab.id,
      );
      return;
    }

    String nextActiveId = state.activeTabId;
    if (state.activeTabId == tabId) {
      final newIndex = (currentIndex - 1 >= 0) ? currentIndex - 1 : 0;
      nextActiveId = updatedTabs[newIndex.clamp(0, updatedTabs.length - 1)].id;
    }

    state = state.copyWith(
      tabs: updatedTabs,
      activeTabId: nextActiveId,
    );
  }

  /// Đổi tên tab
  void renameTab(String tabId, String newTitle) {
    final updatedTabs = state.tabs.map((tab) {
      if (tab.id == tabId) {
        return tab.copyWith(title: newTitle);
      }
      return tab;
    }).toList();
    state = state.copyWith(tabs: updatedTabs);
  }

  void _updateActiveTab(CartTab Function(CartTab current) update) {
    final activeId = state.activeTabId;
    final updatedTabs = state.tabs.map((tab) {
      if (tab.id == activeId) {
        return update(tab);
      }
      return tab;
    }).toList();
    state = state.copyWith(tabs: updatedTabs);
  }

  /// Thêm sản phẩm vào giỏ active
  void addToCart(Product product, {int quantity = 1}) {
    if (!product.allowSale || quantity <= 0) {
      return;
    }
    _updateActiveTab((tab) {
      final currentItems = Map<String, CartItem>.from(tab.items);
      if (currentItems.containsKey(product.id)) {
        final item = currentItems[product.id]!;
        currentItems[product.id] =
            item.copyWith(quantity: item.quantity + quantity);
      } else {
        currentItems[product.id] =
            CartItem(product: product, quantity: quantity);
      }
      return tab.copyWith(items: currentItems);
    });
  }

  /// Cập nhật số lượng sản phẩm trong giỏ active
  void updateQuantity(String productId, int quantity) {
    if (quantity <= 0) {
      removeFromCart(productId);
      return;
    }
    _updateActiveTab((tab) {
      final currentItems = Map<String, CartItem>.from(tab.items);
      if (currentItems.containsKey(productId)) {
        final item = currentItems[productId]!;
        currentItems[productId] = item.copyWith(quantity: quantity);
      }
      return tab.copyWith(items: currentItems);
    });
  }

  /// Cập nhật đơn giá bán tùy chỉnh
  void updatePrice(String productId, double price) {
    _updateActiveTab((tab) {
      final currentItems = Map<String, CartItem>.from(tab.items);
      if (currentItems.containsKey(productId)) {
        final item = currentItems[productId]!;
        currentItems[productId] = item.copyWith(customPrice: price);
      }
      return tab.copyWith(items: currentItems);
    });
  }

  /// Tăng 1 đơn vị số lượng
  void increaseQuantity(String productId) {
    _updateActiveTab((tab) {
      final currentItems = Map<String, CartItem>.from(tab.items);
      if (currentItems.containsKey(productId)) {
        final item = currentItems[productId]!;
        currentItems[productId] = item.copyWith(quantity: item.quantity + 1);
      }
      return tab.copyWith(items: currentItems);
    });
  }

  /// Giảm 1 đơn vị số lượng
  void decreaseQuantity(String productId) {
    _updateActiveTab((tab) {
      final currentItems = Map<String, CartItem>.from(tab.items);
      if (currentItems.containsKey(productId)) {
        final item = currentItems[productId]!;
        if (item.quantity <= 1) {
          currentItems.remove(productId);
        } else {
          currentItems[productId] = item.copyWith(quantity: item.quantity - 1);
        }
      }
      return tab.copyWith(items: currentItems);
    });
  }

  /// Xóa sản phẩm khỏi giỏ active
  void removeFromCart(String productId) {
    _updateActiveTab((tab) {
      final currentItems = Map<String, CartItem>.from(tab.items);
      currentItems.remove(productId);
      return tab.copyWith(items: currentItems);
    });
  }

  /// Xóa toàn bộ sản phẩm và thông tin của giỏ hàng active
  void clearActiveCart() {
    _updateActiveTab((tab) {
      return tab.copyWith(
        items: {},
        clearCustomer: true,
        discount: 0.0,
        isDiscountPercent: false,
        note: '',
        clearActiveOrderId: true,
      );
    });
  }

  /// Alias cho clearActiveCart (đáp ứng API cũ)
  void clearCart() {
    clearActiveCart();
  }

  /// Gán khách hàng cho đơn active
  void setCustomer(Customer? customer) {
    _updateActiveTab((tab) {
      if (customer == null) {
        return tab.copyWith(clearCustomer: true);
      }
      return tab.copyWith(customer: customer);
    });
  }

  /// Gán chiết khấu cho đơn active
  void setDiscount(double discount, bool isPercent) {
    _updateActiveTab((tab) {
      return tab.copyWith(
        discount: discount,
        isDiscountPercent: isPercent,
      );
    });
  }

  /// Gán ghi chú cho đơn active
  void setNote(String note) {
    _updateActiveTab((tab) {
      return tab.copyWith(note: note);
    });
  }

  /// Gán mã đơn tạm lưu trên server
  void setActiveOrderId(String? orderId) {
    _updateActiveTab((tab) {
      if (orderId == null) {
        return tab.copyWith(clearActiveOrderId: true);
      }
      return tab.copyWith(activeOrderId: orderId);
    });
  }

  /// Nạp lại danh sách sản phẩm (dùng khi khôi phục đơn tạm từ InvoicesPage)
  void populateCart(
    List<OrderItem> items,
    List<Product> allProducts, {
    String? orderId,
    Customer? customer,
    double? discount,
    bool? isDiscountPercent,
    String? note,
  }) {
    final newCart = <String, CartItem>{};
    for (final item in items) {
      final product = allProducts.firstWhere(
        (p) => p.id == item.productId,
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
        ),
      );
      newCart[item.productId] = CartItem(
        product: product,
        quantity: item.quantity,
        customPrice: item.price != product.price ? item.price : null,
      );
    }

    _updateActiveTab((tab) {
      return tab.copyWith(
        items: newCart,
        activeOrderId: orderId,
        customer: customer,
        discount: discount,
        isDiscountPercent: isDiscountPercent,
        note: note,
      );
    });
  }
}

/// Notifier giỏ hàng đơn (Backward-compatible StateNotifier<Map<String, CartItem>>)
class CartNotifier extends StateNotifier<Map<String, CartItem>> {
  final Ref? _ref;
  final MultiCartNotifier? _multiCartNotifier;

  CartNotifier({Ref? ref, MultiCartNotifier? multiCartNotifier})
      : _ref = ref,
        _multiCartNotifier = multiCartNotifier,
        super(multiCartNotifier != null
            ? multiCartNotifier.state.activeTab.items
            : (ref != null
                ? ref.read(multiCartProvider).activeTab.items
                : {})) {
    if (_ref != null) {
      state = _ref.read(multiCartProvider).activeTab.items;
      _ref.listen<MultiCartState>(multiCartProvider, (previous, next) {
        final newItems = next.activeTab.items;
        if (state != newItems) {
          state = newItems;
        }
      });
    } else if (_multiCartNotifier != null) {
      state = _multiCartNotifier.state.activeTab.items;
      _multiCartNotifier.addListener((multiState) {
        final newItems = multiState.activeTab.items;
        if (state != newItems) {
          state = newItems;
        }
      });
    }
  }

  MultiCartNotifier? get _targetMultiNotifier =>
      _multiCartNotifier ?? _ref?.read(multiCartProvider.notifier);

  void addToCart(Product product, {int quantity = 1}) {
    final multi = _targetMultiNotifier;
    if (multi != null) {
      multi.addToCart(product, quantity: quantity);
      state = multi.state.activeTab.items;
      return;
    }

    if (!product.allowSale || quantity <= 0) {
      return;
    }
    if (state.containsKey(product.id)) {
      final currentItem = state[product.id]!;
      state = {
        ...state,
        product.id:
            currentItem.copyWith(quantity: currentItem.quantity + quantity),
      };
    } else {
      state = {
        ...state,
        product.id: CartItem(product: product, quantity: quantity),
      };
    }
  }

  void updateQuantity(String productId, int quantity) {
    final multi = _targetMultiNotifier;
    if (multi != null) {
      multi.updateQuantity(productId, quantity);
      state = multi.state.activeTab.items;
      return;
    }

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
    final multi = _targetMultiNotifier;
    if (multi != null) {
      multi.updatePrice(productId, price);
      state = multi.state.activeTab.items;
      return;
    }

    if (state.containsKey(productId)) {
      final currentItem = state[productId]!;
      state = {
        ...state,
        productId: currentItem.copyWith(customPrice: price),
      };
    }
  }

  void increaseQuantity(String productId) {
    final multi = _targetMultiNotifier;
    if (multi != null) {
      multi.increaseQuantity(productId);
      state = multi.state.activeTab.items;
      return;
    }

    if (state.containsKey(productId)) {
      final currentItem = state[productId]!;
      state = {
        ...state,
        productId: currentItem.copyWith(quantity: currentItem.quantity + 1),
      };
    }
  }

  void decreaseQuantity(String productId) {
    final multi = _targetMultiNotifier;
    if (multi != null) {
      multi.decreaseQuantity(productId);
      state = multi.state.activeTab.items;
      return;
    }

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
    final multi = _targetMultiNotifier;
    if (multi != null) {
      multi.removeFromCart(productId);
      state = multi.state.activeTab.items;
      return;
    }

    final updated = Map<String, CartItem>.from(state);
    updated.remove(productId);
    state = updated;
  }

  void clearCart() {
    final multi = _targetMultiNotifier;
    if (multi != null) {
      multi.clearCart();
      state = multi.state.activeTab.items;
      return;
    }

    state = {};
  }

  void populateCart(
    List<OrderItem> items,
    List<Product> allProducts, {
    String? orderId,
    Customer? customer,
    double? discount,
    bool? isDiscountPercent,
    String? note,
  }) {
    final multi = _targetMultiNotifier;
    if (multi != null) {
      multi.populateCart(
        items,
        allProducts,
        orderId: orderId,
        customer: customer,
        discount: discount,
        isDiscountPercent: isDiscountPercent,
        note: note,
      );
      state = multi.state.activeTab.items;
      return;
    }

    final newCart = <String, CartItem>{};
    for (final item in items) {
      final product = allProducts.firstWhere(
        (p) => p.id == item.productId,
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
        ),
      );
      newCart[item.productId] = CartItem(
        product: product,
        quantity: item.quantity,
        customPrice: item.price != product.price ? item.price : null,
      );
    }
    state = newCart;
  }
}

/// Cache lưu trữ trạng thái giỏ hàng theo từng chi nhánh, gắn liền với ProviderContainer
final branchCartsCacheProvider =
    StateProvider<Map<String, MultiCartState>>((ref) => {});

/// Provider quản lý toàn bộ hệ thống đa giỏ hàng POS
final multiCartProvider =
    StateNotifierProvider<MultiCartNotifier, MultiCartState>((ref) {
  final branchId = ref.watch(selectedPOSBranchProvider);
  final cache = ref.read(branchCartsCacheProvider);

  final initial =
      cache[branchId] ?? MultiCartNotifier.createInitialState(branchId);
  cache[branchId] = initial;

  return MultiCartNotifier(
    currentBranchId: branchId,
    initialState: initial,
    onStateChanged: (newState) {
      cache[branchId] = newState;
    },
  );
});

/// Provider giỏ hàng chính (tương thích ngược 100% với toàn bộ codebase cũ)
final cartProvider =
    StateNotifierProvider<CartNotifier, Map<String, CartItem>>((ref) {
  ref.watch(selectedPOSBranchProvider);
  return CartNotifier(ref: ref);
});

/// Provider tính tổng số lượng sản phẩm trong giỏ của active tab
final cartTotalItemsProvider = Provider<int>((ref) {
  final multiCart = ref.watch(multiCartProvider);
  return multiCart.activeTab.totalItems;
});

/// Provider tính tổng số tiền hàng của active tab
final cartTotalAmountProvider = Provider<double>((ref) {
  final multiCart = ref.watch(multiCartProvider);
  return multiCart.activeTab.totalAmount;
});

/// Provider quản lý mã đơn lưu tạm đang hoạt động
final activeOrderIdProvider = StateProvider<String?>((ref) => null);
