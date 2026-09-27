import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/services/filter_storage_service.dart';
import '../../../core/utils/combo_helper.dart';
import '../../../domain/entities/product.dart';
import '../../common/widgets/product_image_thumbnail.dart';
import '../widgets/pos_cart_tab_bar.dart';
import '../widgets/pos_category_bar.dart';
import 'pos_checkout_page.dart';

class POSPage extends ConsumerStatefulWidget {
  const POSPage({super.key});

  @override
  ConsumerState<POSPage> createState() => _POSPageState();
}

class _POSPageState extends ConsumerState<POSPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _selectedCategoryId = 'all';
  String _selectedCategoryName = 'Tất cả';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productListProvider);
    final cart = ref.watch(cartProvider);
    final totalItems = ref.watch(cartTotalItemsProvider);
    final totalAmount = ref.watch(cartTotalAmountProvider);
    final selectedBranch = ref.watch(selectedPOSBranchProvider);
    final posBranchName = ref.watch(posBranchNameProvider);
    final user = ref.watch(authProvider);
    final canSwitchBranch = user != null &&
        (user.isAdmin || user.isSupervisor || user.canSwitchStore);
    final l10n = AppLocalizations.of(context)!;

    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        centerTitle: true,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(l10n.salesTitle,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            InkWell(
              key: const Key('pos_branch_switcher_button'),
              onTap:
                  canSwitchBranch ? () => _showBranchSelector(context) : null,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      posBranchName,
                      style: TextStyle(
                        fontSize: 11,
                        color: canSwitchBranch
                            ? AppColors.primary
                            : AppColors.textSecondary,
                        fontWeight: canSwitchBranch
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    if (canSwitchBranch) ...[
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.arrow_drop_down,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (canSwitchBranch)
            IconButton(
              key: const Key('pos_branch_switcher_action'),
              icon: const Icon(Icons.storefront, color: AppColors.primary),
              tooltip: 'Đổi chi nhánh',
              onPressed: () => _showBranchSelector(context),
            ),
        ],
        backgroundColor: AppColors.white,
      ),
      body: Column(
        children: [
          // Thanh tab giỏ hàng đa đơn
          const PosCartTabBar(),
          // Thanh tìm kiếm sản phẩm nhanh
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: l10n.searchPOSHint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                fillColor: AppColors.white,
                filled: true,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border),
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // Thanh cuộn lọc nhóm hàng / danh mục
          PosCategoryBar(
            selectedCategoryId: _selectedCategoryId,
            onCategorySelected: (catId, catName) {
              setState(() {
                _selectedCategoryId = catId;
                _selectedCategoryName = catName;
              });
            },
          ),
          const SizedBox(height: 6),
          // Danh sách sản phẩm
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final filtered = products.where((p) {
                  // Hide products that are disabled / stopped selling
                  if (!p.allowSale) return false;

                  // 1) Lọc theo danh mục
                  if (_selectedCategoryId != 'all' &&
                      _selectedCategoryId.isNotEmpty) {
                    final catNameLower =
                        _selectedCategoryName.trim().toLowerCase();
                    final catIdLower = _selectedCategoryId.trim().toLowerCase();
                    final pCatLower = p.category.trim().toLowerCase();
                    final matchesCategory = pCatLower == catNameLower ||
                        pCatLower == catIdLower ||
                        pCatLower.contains(catNameLower) ||
                        catNameLower.contains(pCatLower);
                    if (!matchesCategory) return false;
                  }

                  // 2) Lọc theo từ khóa tìm kiếm
                  final query = _searchQuery.toLowerCase().trim();
                  if (query.isNotEmpty) {
                    final matchesSearch =
                        p.name.toLowerCase().contains(query) ||
                            p.code.toLowerCase().contains(query) ||
                            (p.brand ?? '').toLowerCase().contains(query) ||
                            p.category.toLowerCase().contains(query);
                    if (!matchesSearch) return false;
                  }

                  return true;
                }).toList();

                if (filtered.isEmpty) {
                  return Center(child: Text(l10n.noProductsFound));
                }

                return ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final product = filtered[index];
                    final cartItem = cart[product.id];
                    final quantityInCart = cartItem?.quantity ?? 0;
                    final effectiveStock = ComboHelper.getAvailableStock(
                      product: product,
                      branchId: selectedBranch,
                      allProducts: products,
                    );

                    final branchStocksText =
                        _formatBranchStocks(product.branchStocks);

                    return Container(
                      decoration: BoxDecoration(
                        color: AppColors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Icon/Ảnh sản phẩm
                          ProductImageThumbnail(
                            imageUrl:
                                product.primaryImageUrl ?? product.imageUrl,
                            productName: product.name,
                            categoryName: product.category,
                            size: 52,
                            borderRadius: 8,
                          ),
                          const SizedBox(width: 12),
                          // Thông tin chi tiết sản phẩm
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        product.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                            color: AppColors.textPrimary),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    if (product.isCombo) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          'COMBO',
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${l10n.productCode}: ${product.code}',
                                  style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11),
                                ),
                                if (product.isCombo &&
                                    product.comboComponents.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Gồm: ${product.comboComponents.map((c) => "${c.quantity}x ${c.productName}").join(", ")}',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (branchStocksText.isNotEmpty) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    branchStocksText,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 11,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${currencyFormat.format(product.price)} đ',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.primary,
                                          fontSize: 13),
                                    ),
                                    const SizedBox(width: 8),
                                    _buildStockBadge(effectiveStock, product),
                                  ],
                                )
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Nút thêm/bớt số lượng
                          _buildCartControl(
                              product, quantityInCart, effectiveStock, l10n),
                        ],
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: LoadingIndicator()),
              error: (e, _) => Center(child: ErrorView(e)),
            ),
          ),
          // Thanh trạng thái giỏ hàng dưới cùng (nếu giỏ hàng không trống)
          if (totalItems > 0)
            _buildCartSummaryBar(
                context, totalItems, totalAmount, currencyFormat, l10n),
        ],
      ),
    );
  }

  // Widget quản lý thêm/bớt số lượng
  Widget _buildCartControl(Product product, int quantityInCart,
      int effectiveStock, AppLocalizations l10n) {
    if (quantityInCart == 0) {
      final isOutOfStock = effectiveStock <= 0;
      return InkWell(
        key: Key('pos_add_to_cart_${product.id}'),
        onTap: () {
          if (isOutOfStock) {
            ScaffoldMessenger.of(context).clearSnackBars();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(l10n.outOfStockAlert),
                duration: const Duration(milliseconds: 1500),
              ),
            );
            return;
          }
          ref.read(cartProvider.notifier).addToCart(product);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: isOutOfStock
                ? AppColors.grey400.withOpacity(0.12)
                : AppColors.primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.add,
            color: isOutOfStock ? AppColors.grey400 : AppColors.primary,
            size: 20,
          ),
        ),
      );
    }

    final isLimitReached = quantityInCart >= effectiveStock;
    return Row(
      children: [
        // Nút trừ
        GestureDetector(
          onTap: () =>
              ref.read(cartProvider.notifier).decreaseQuantity(product.id),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.textDisabled),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.remove,
                size: 14, color: AppColors.textSecondary),
          ),
        ),
        const SizedBox(width: 10),
        // Số lượng
        Text(
          '$quantityInCart',
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: AppColors.textPrimary),
        ),
        const SizedBox(width: 10),
        // Nút cộng
        GestureDetector(
          onTap: () {
            if (isLimitReached) {
              ScaffoldMessenger.of(context).clearSnackBars();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(l10n.stockLimitAlert(effectiveStock)),
                  duration: const Duration(milliseconds: 1500),
                ),
              );
              return;
            }
            ref.read(cartProvider.notifier).increaseQuantity(product.id);
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(
                color: isLimitReached ? AppColors.grey400 : AppColors.primary,
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.add,
              size: 14,
              color: isLimitReached ? AppColors.grey400 : AppColors.primary,
            ),
          ),
        ),
      ],
    );
  }

  // Widget hiển thị thanh tổng tiền/giỏ hàng nổi ở dưới
  Widget _buildCartSummaryBar(BuildContext context, int totalItems,
      double totalAmount, NumberFormat format, AppLocalizations l10n) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.08),
            blurRadius: 10,
            offset: const Offset(0, -2),
          )
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.cartSummaryTitle(totalItems),
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 2),
              Text(
                '${format.format(totalAmount)} đ',
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: AppColors.primary),
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              final activeTab = ref.read(multiCartProvider).activeTab;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => POSCheckoutPage(
                    initialCustomer: activeTab.customer,
                    initialDiscount: activeTab.discount,
                    isDiscountPercent: activeTab.isDiscountPercent,
                    initialNote: activeTab.note,
                  ),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: Text(
              l10n.doneBtn,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildStockBadge(int effectiveStock, Product product) {
    final String label;
    final Color color;
    if (effectiveStock <= 0) {
      label = 'Hết hàng';
      color = AppColors.danger;
    } else if (effectiveStock <= (product.minStock ?? 5)) {
      label = 'Sắp hết';
      color = AppColors.warningDark;
    } else {
      label = 'Còn hàng';
      color = AppColors.success;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _formatBranchStocks(Map<String, int> branchStocks) {
    if (branchStocks.isEmpty) return '';
    return branchStocks.entries.map((entry) {
      final branchName = _getBranchShortName(entry.key);
      return '$branchName: ${entry.value}';
    }).join(' | ');
  }

  String _getBranchShortName(String key) {
    final lower = key.trim().toLowerCase();
    if (lower == 'store_001' ||
        lower == 'branch_1' ||
        lower == 'đt' ||
        lower == 'dt' ||
        lower.contains('đông thắng') ||
        lower.contains('dong thang')) {
      return 'ĐT';
    }
    if (lower == 'store_002' ||
        lower == 'branch_2' ||
        lower == 'tb' ||
        lower.contains('thới bình') ||
        lower.contains('thoi binh') ||
        lower.contains('thời bình')) {
      return 'TB';
    }

    final storeMatch =
        RegExp(r'^(?:store|branch)[_-]?(\d+)$', caseSensitive: false)
            .firstMatch(key.trim());
    if (storeMatch != null) {
      final numStr = storeMatch.group(1)!;
      final numVal = int.tryParse(numStr) ?? 0;
      return 'CN$numVal';
    }

    return key;
  }

  void _showBranchSelector(BuildContext context) {
    final availableStoresAsync = ref.read(availableStoresProvider);
    final storesMap = availableStoresAsync.valueOrNull ??
        const {
          'store_001': 'Chi nhánh Đông Thắng',
          'store_002': 'Chi nhánh Thới Bình',
        };
    final currentBranch = ref.read(selectedPOSBranchProvider);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Text(
                  'Chọn chi nhánh làm việc',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const Divider(height: 1),
              ...storesMap.entries.map((entry) {
                final isSelected = entry.key == currentBranch;
                return ListTile(
                  leading: Icon(
                    Icons.store,
                    color: isSelected ? AppColors.primary : AppColors.grey400,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.textPrimary,
                    ),
                  ),
                  trailing: isSelected
                      ? const Icon(Icons.check, color: AppColors.primary)
                      : null,
                  onTap: () {
                    final newBranch = entry.key;
                    Navigator.pop(ctx);
                    if (newBranch == currentBranch) return;

                    final user = ref.read(authProvider);
                    if (user != null &&
                        (user.isAdmin ||
                            user.isSupervisor ||
                            user.canSwitchStore)) {
                      ref
                          .read(filterStorageServiceProvider)
                          .saveSelectedStore(newBranch, user.username);
                      ref.read(selectedStoreIdProvider.notifier).state =
                          newBranch;
                    }
                    ref.read(selectedPOSBranchProvider.notifier).state =
                        newBranch;
                    ScaffoldMessenger.of(context).clearSnackBars();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Đã chuyển sang ${entry.value}'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                );
              }),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}
