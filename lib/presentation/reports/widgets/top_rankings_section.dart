import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/customers/customers_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/reports/overview_kpi_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/overview_kpis.dart';
import '../../../domain/entities/product.dart';
import '../../common/widgets/product_image_thumbnail.dart';
import '../../customers/pages/customer_detail_page.dart';
import '../../customers/pages/customers_page.dart';
import '../../products/pages/product_detail_page.dart';
import '../../products/pages/products_page.dart';

/// Sub-widget Xếp Hạng Bán Chạy & Khách Hàng Thân Thiết (R5 - Top Rankings Section)
/// - Top 5/10 Hàng bán chạy: Hỗ trợ chuyển đổi nhanh giữa lọc [Theo Doanh thu] và [Theo Số lượng],
///   hiển thị thứ hạng 1-2-3 (vàng, bạc, đồng), hình ảnh thumbnail, số lượng và doanh thu.
/// - Top Khách hàng mua nhiều nhất trong kỳ lọc: avatar, tên, số điện thoại, số đơn và tổng chi tiêu.
class TopRankingsSection extends ConsumerWidget {
  const TopRankingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final topProductsAsync = ref.watch(topSellingProductsRankingProvider);
    final topCustomersAsync = ref.watch(topCustomersRankingProvider);
    final sortBy = ref.watch(topSellingSortByProvider);
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Column(
      children: [
        // Card 1: Top Hàng Bán Chạy
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'Top hàng bán chạy',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ProductsPage(),
                          ),
                        );
                      },
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Xem tất cả',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.chevron_right,
                                size: 14, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Segmented Tabs: Theo Doanh thu / Theo Số lượng
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildSortTab(
                      label: 'Doanh thu',
                      isSelected: sortBy == TopProductsSortBy.revenue,
                      onTap: () {
                        ref
                            .read(topSellingSortByProvider.notifier)
                            .state = TopProductsSortBy.revenue;
                      },
                    ),
                    _buildSortTab(
                      label: 'Số lượng',
                      isSelected: sortBy == TopProductsSortBy.quantity,
                      onTap: () {
                        ref
                            .read(topSellingSortByProvider.notifier)
                            .state = TopProductsSortBy.quantity;
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              topProductsAsync.when(
                data: (products) =>
                    _buildProductsList(context, ref, products, currencyFormat),
                loading: () => const SizedBox(
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => SizedBox(
                  height: 60,
                  child: Center(
                    child: Text(
                      'Lỗi tải top bán chạy: $e',
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Card 2: Top Khách Hàng Chi Tiêu Nhiều Nhất
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 3,
                          height: 14,
                          decoration: BoxDecoration(
                            color: AppColors.chartPurple,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Flexible(
                          child: Text(
                            'Top khách hàng chi tiêu',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const CustomersPage(),
                          ),
                        );
                      },
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Xem tất cả',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            SizedBox(width: 2),
                            Icon(Icons.chevron_right,
                                size: 14, color: AppColors.primary),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              topCustomersAsync.when(
                data: (customers) =>
                    _buildCustomersList(context, ref, customers, currencyFormat),
                loading: () => const SizedBox(
                  height: 120,
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (e, _) => SizedBox(
                  height: 60,
                  child: Center(
                    child: Text(
                      'Lỗi tải khách hàng: $e',
                      style: const TextStyle(
                          color: AppColors.danger, fontSize: 12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSortTab({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 3,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? AppColors.primary : Colors.black54,
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // Top Products List
  // ===========================================================================
  Widget _buildProductsList(
    BuildContext context,
    WidgetRef ref,
    List<ProductRankingItem> products,
    NumberFormat format,
  ) {
    if (products.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'Chưa có dữ liệu bán hàng trong kỳ',
            style: TextStyle(color: Colors.black38, fontSize: 12),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: products.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 16, color: AppColors.divider),
      itemBuilder: (context, index) {
        final item = products[index];
        final rank = index + 1;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              final allProducts = ref.read(allStoresProductsProvider).value;
              final storeProducts = ref.read(productListProvider).value;
              Product? resolvedProduct;
              if (allProducts != null) {
                resolvedProduct =
                    allProducts.where((p) => p.id == item.productId).firstOrNull;
              }
              if (resolvedProduct == null && storeProducts != null) {
                resolvedProduct =
                    storeProducts.where((p) => p.id == item.productId).firstOrNull;
              }
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ProductDetailPage(
                    product: resolvedProduct,
                    productId: item.productId,
                  ),
                ),
              );
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
              child: Row(
                children: [
                  // Rank Badge (Vàng / Bạc / Đồng / Xám)
                  _buildRankBadge(rank),

                  const SizedBox(width: 8),

                  // Product Thumbnail
                  ProductImageThumbnail(
                    imageUrl: item.imageUrl,
                    productName: item.productName,
                    categoryName: item.categoryName,
                    size: 38,
                    borderRadius: 6,
                  ),

                  const SizedBox(width: 10),

                  // Product Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.productName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Đã bán: ${item.quantity}',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Revenue
                  Text(
                    '${format.format(item.revenue)} đ',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Colors.black38,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ===========================================================================
  // Top Customers List
  // ===========================================================================
  Widget _buildCustomersList(
    BuildContext context,
    WidgetRef ref,
    List<CustomerRankingItem> customers,
    NumberFormat format,
  ) {
    if (customers.isEmpty) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: Text(
            'Chưa có dữ liệu khách hàng trong kỳ',
            style: TextStyle(color: Colors.black38, fontSize: 12),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: customers.length,
      separatorBuilder: (_, __) =>
          const Divider(height: 16, color: AppColors.divider),
      itemBuilder: (context, index) {
        final item = customers[index];
        final rank = index + 1;

        final initial = item.customerName.isNotEmpty
            ? item.customerName.trim().substring(0, 1).toUpperCase()
            : 'K';

        return Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final customersList =
                  ref.read(customerListNotifierProvider).value;
              Customer? resolvedCustomer;
              if (customersList != null) {
                resolvedCustomer = customersList
                    .where((c) => c.id == item.customerId)
                    .firstOrNull;
              }
              if (resolvedCustomer == null) {
                try {
                  resolvedCustomer = await ref
                      .read(customerRepositoryProvider)
                      .fetchById(item.customerId);
                } catch (_) {}
              }
              resolvedCustomer ??= Customer(
                id: item.customerId,
                name: item.customerName,
                phone: item.phoneNumber ?? '',
                email: '',
                address: '',
                purchases: const [],
              );
              if (!context.mounted) return;
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      CustomerDetailPage(customer: resolvedCustomer!),
                ),
              );
            },
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: 4.0, horizontal: 4.0),
              child: Row(
                children: [
                  _buildRankBadge(rank),

                  const SizedBox(width: 8),

                  // Avatar Initials
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: AppColors.chartPurple.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        initial,
                        style: const TextStyle(
                          color: AppColors.chartPurple,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  // Customer details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.customerName,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.phoneNumber != null &&
                                  item.phoneNumber!.isNotEmpty
                              ? '${item.phoneNumber} • ${item.orderCount} đơn'
                              : '${item.orderCount} đơn hàng',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Total spent
                  Text(
                    '${format.format(item.totalSpent)} đ',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: Colors.black38,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRankBadge(int rank) {
    Color badgeColor;
    Color textColor = Colors.white;

    if (rank == 1) {
      badgeColor = const Color(0xFFEAB308); // Gold
    } else if (rank == 2) {
      badgeColor = const Color(0xFF94A3B8); // Silver
    } else if (rank == 3) {
      badgeColor = const Color(0xFFD97706); // Bronze
    } else {
      badgeColor = Colors.grey.shade200;
      textColor = Colors.black54;
    }

    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        color: badgeColor,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          '$rank',
          style: TextStyle(
            color: textColor,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
