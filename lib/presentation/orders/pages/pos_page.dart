import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';

import '../../../application/products/products_providers.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../application/reports/overview_providers.dart';
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

    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: InkWell(
          onTap: user?.isAdmin == true ? () => _showStoreBranchSelectorBottomSheet(context, ref) : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bán hàng', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      storeNameAsync.when(
                        data: (name) {
                          final currentStoreId = ref.watch(currentStoreIdProvider);
                          final branchId = ref.watch(selectedPOSBranchProvider);
                          final mockBranches = getMockBranches(currentStoreId);
                          final branchName = mockBranches.firstWhere((b) => b.id == branchId).name;
                          return Text(
                            '$name - $branchName',
                            style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.normal),
                          );
                        },
                        loading: () => const Text('Đang tải...', style: TextStyle(fontSize: 11, color: Colors.black38)),
                        error: (_, __) => const Text('Không rõ cửa hàng', style: TextStyle(fontSize: 11, color: Colors.red)),
                      ),
                      if (user?.isAdmin == true) ...[
                        const SizedBox(width: 4),
                        const Icon(Icons.arrow_drop_down, size: 16, color: Colors.black54),
                      ]
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Tính năng quét mã vạch đang được khởi động...')),
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
                hintText: 'Tìm tên, mã hàng, thương hiệu...',
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
                  borderSide: const BorderSide(color: Color(0xFFE1E2E4)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF0067AC)),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFE1E2E4)),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      p.brand.toLowerCase().contains(query) ||
                      p.category.toLowerCase().contains(query);
                }).toList();

                if (filtered.isEmpty) {
                  return const Center(child: Text('Không tìm thấy sản phẩm phù hợp'));
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
                        border: Border.all(color: const Color(0xFFE1E2E4)),
                      ),
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Icon/Ảnh sản phẩm
                          CircleAvatar(
                            radius: 24,
                            backgroundColor: const Color(0xFF0067AC).withOpacity(0.06),
                            child: Icon(Icons.shopping_bag_outlined, color: const Color(0xFF0067AC), size: 22),
                          ),
                          const SizedBox(width: 12),
                          // Thông tin chi tiết sản phẩm
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Mã: ${product.code}',
                                  style: const TextStyle(color: Colors.black54, fontSize: 11),
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(
                                      '${currencyFormat.format(product.price)} đ',
                                      style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0067AC), fontSize: 13),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      'Tồn: ${product.stock}',
                                      style: TextStyle(
                                        color: product.stock == 0 ? Colors.red : Colors.black45,
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
                          _buildCartControl(product, quantityInCart),
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
          if (totalItems > 0) _buildCartSummaryBar(context, totalItems, totalAmount, currencyFormat),
        ],
      ),
    );
  }

  // Widget quản lý thêm/bớt số lượng
  Widget _buildCartControl(Product product, int quantityInCart) {
    if (quantityInCart == 0) {
      return InkWell(
        onTap: () {
          if (product.stock <= 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Sản phẩm đã hết hàng trong kho!')),
            );
            return;
          }
          ref.read(cartProvider.notifier).addToCart(product);
        },
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: const Color(0xFF0067AC).withOpacity(0.08),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.add, color: Color(0xFF0067AC), size: 20),
        ),
      );
    }

    return Row(
      children: [
        // Nút trừ
        GestureDetector(
          onTap: () => ref.read(cartProvider.notifier).decreaseQuantity(product.id),
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
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
        ),
        const SizedBox(width: 10),
        // Nút cộng
        GestureDetector(
          onTap: () {
            if (quantityInCart >= product.stock) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Không thể vượt quá số lượng tồn kho (${product.stock})!')),
              );
              return;
            }
            ref.read(cartProvider.notifier).increaseQuantity(product.id);
          },
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(color: const Color(0xFF0067AC)),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.add, size: 14, color: Color(0xFF0067AC)),
          ),
        ),
      ],
    );
  }

  // Widget hiển thị thanh tổng tiền/giỏ hàng nổi ở dưới
  Widget _buildCartSummaryBar(BuildContext context, int totalItems, double totalAmount, NumberFormat format) {
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
                'Giỏ hàng ($totalItems sản phẩm)',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 2),
              Text(
                '${format.format(totalAmount)} đ',
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Color(0xFF0067AC)),
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
              backgroundColor: const Color(0xFF0067AC),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text(
              'Xong',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          )
        ],
      ),
    );
  }

  // Hộp thoại chọn Cửa hàng & Chi nhánh (Chỉ dành cho Admin)
  void _showStoreBranchSelectorBottomSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (sheetContext) {
        return Consumer(
          builder: (consumerContext, sheetRef, child) {
            final currentStoreId = sheetRef.watch(currentStoreIdProvider);
            final currentBranchId = sheetRef.watch(selectedPOSBranchProvider);
            final storesAsync = sheetRef.watch(availableStoresProvider);
            final mockBranches = getMockBranches(currentStoreId);

            return Container(
              padding: const EdgeInsets.only(top: 16, bottom: 32, left: 16, right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Chọn cửa hàng & chi nhánh bán hàng (Admin)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const Divider(color: Color(0xFFEEEEEE)),
                  const SizedBox(height: 8),
                  const Text(
                    'Cửa hàng hoạt động',
                    style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  storesAsync.when(
                    data: (storesMap) => DropdownButtonFormField<String>(
                      value: currentStoreId,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: storesMap.entries.map((e) {
                        return DropdownMenuItem(value: e.key, child: Text(e.value));
                      }).toList(),
                      onChanged: (newStoreId) {
                        if (newStoreId != null) {
                          sheetRef.read(selectedStoreIdProvider.notifier).state = newStoreId;
                          sheetRef.invalidate(productListProvider);
                          sheetRef.read(selectedPOSBranchProvider.notifier).state = 'branch_1';
                        }
                      },
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text('Lỗi: $e'),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Chi nhánh xuất kho',
                    style: TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: currentBranchId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: mockBranches.map((b) {
                      return DropdownMenuItem(value: b.id, child: Text(b.name));
                    }).toList(),
                    onChanged: (newBranchId) {
                      if (newBranchId != null) {
                        sheetRef.read(selectedPOSBranchProvider.notifier).state = newBranchId;
                      }
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
