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
import '../../../domain/entities/product.dart';
import 'pos_checkout_page.dart';

class POSPage extends ConsumerStatefulWidget {
  const POSPage({super.key});

  @override
  ConsumerState<POSPage> createState() => _POSPageState();
}

class _POSPageState extends ConsumerState<POSPage> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

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
    final user = ref.watch(authProvider);
    final storeNameAsync = ref.watch(currentStoreNameProvider);
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
            storeNameAsync.when(
              data: (name) {
                return Text(
                  name,
                  style: const TextStyle(
                      fontSize: 11,
                      color: Colors.black54,
                      fontWeight: FontWeight.normal),
                );
              },
              loading: () => Text(l10n.loadingText,
                  style: const TextStyle(fontSize: 11, color: Colors.black38)),
              error: (_, __) => Text(l10n.unknownStore,
                  style: const TextStyle(fontSize: 11, color: Colors.red)),
            ),
          ],
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.barcodeScannerStarting)),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          // Thanh tìm kiếm sản phẩm nhanh
          Padding(
            padding: const EdgeInsets.all(12.0),
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
                fillColor: Colors.white,
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
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (v) => setState(() => _searchQuery = v),
            ),
          ),
          // Danh sách sản phẩm
          Expanded(
            child: productsAsync.when(
              data: (products) {
                final filtered = products.where((p) {
                  final query = _searchQuery.toLowerCase().trim();
                  if (query.isEmpty) return true;
                  return p.name.toLowerCase().contains(query) ||
                      p.code.toLowerCase().contains(query) ||
                      (p.brand ?? '').toLowerCase().contains(query) ||
                      p.category.toLowerCase().contains(query);
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

                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Icon/Ảnh sản phẩm
                          CircleAvatar(
                            radius: 24,
                            backgroundColor:
                                AppColors.primary.withOpacity(0.06),
                            child: const Icon(Icons.shopping_bag_outlined,
                                color: AppColors.primary, size: 22),
                          ),
                          const SizedBox(width: 12),
                          // Thông tin chi tiết sản phẩm
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14,
                                      color: Colors.black87),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${l10n.productCode}: ${product.code}',
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 11),
                                ),
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
                                    Text(
                                      '${l10n.stockLabel}: ${product.stock}',
                                      style: TextStyle(
                                        color: product.stock == 0
                                            ? Colors.red
                                            : Colors.black45,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                )
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Nút thêm/bớt số lượng
                          _buildCartControl(product, quantityInCart, l10n),
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
  Widget _buildCartControl(
      Product product, int quantityInCart, AppLocalizations l10n) {
    if (quantityInCart == 0) {
      return InkWell(
        onTap: () {
          if (product.stock <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.outOfStockAlert)),
            );
            return;
          }
          ref.read(cartProvider.notifier).addToCart(product);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add, color: AppColors.primary, size: 20),
        ),
      );
    }

    return Row(
      children: [
        // Nút trừ
        GestureDetector(
          onTap: () =>
              ref.read(cartProvider.notifier).decreaseQuantity(product.id),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black26),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.remove, size: 14, color: Colors.black54),
          ),
        ),
        const SizedBox(width: 10),
        // Số lượng
        Text(
          '$quantityInCart',
          style: const TextStyle(
              fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
        ),
        const SizedBox(width: 10),
        // Nút cộng
        GestureDetector(
          onTap: () {
            if (quantityInCart >= product.stock) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.stockLimitAlert(product.stock))),
              );
              return;
            }
            ref.read(cartProvider.notifier).increaseQuantity(product.id);
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, size: 14, color: AppColors.primary),
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
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
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
                style: const TextStyle(fontSize: 12, color: Colors.black54),
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
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const POSCheckoutPage(),
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
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
}
