import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';

import 'package:flutter/services.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../application/customers/customers_providers.dart';
import '../../../application/notifications/notification_dispatcher.dart';
import '../../../application/orders/cart_providers.dart';
import '../../../application/orders/orders_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/utils/code_generator_helper.dart';
import '../../../core/utils/combo_helper.dart';
import '../../../domain/entities/customer.dart';
import '../../../domain/entities/order.dart';
import '../../../domain/entities/order_item.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/user_account.dart';
import '../../products/pages/add_product_page.dart';
import 'pos_payment_page.dart';
import '../../../core/utils/order_code_resolver.dart';

class POSCheckoutPage extends ConsumerStatefulWidget {
  final Customer? initialCustomer;
  final double initialDiscount;
  final bool isDiscountPercent;
  final String? initialNote;

  const POSCheckoutPage({
    super.key,
    this.initialCustomer,
    this.initialDiscount = 0.0,
    this.isDiscountPercent = false,
    this.initialNote,
  });

  @override
  ConsumerState<POSCheckoutPage> createState() => _POSCheckoutPageState();
}

class _POSCheckoutPageState extends ConsumerState<POSCheckoutPage> {
  // Trạng thái khách hàng được chọn (Mặc định null nghĩa là "Khách lẻ")
  Customer? _selectedCustomer;
  bool _isSaving = false;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  final TextEditingController _orderNoteController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCustomer = widget.initialCustomer;
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _searchQuery) {
        setState(() => _searchQuery = q);
      }
    });

    final currentTabNote = ref.read(multiCartProvider).activeTab.note;
    if (widget.initialNote != null && widget.initialNote!.isNotEmpty) {
      _orderNoteController.text = widget.initialNote!;
      if (currentTabNote != widget.initialNote) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(multiCartProvider.notifier).setNote(widget.initialNote!);
          }
        });
      }
    } else if (currentTabNote.isNotEmpty) {
      _orderNoteController.text = currentTabNote;
    }
    _orderNoteController.addListener(() {
      ref.read(multiCartProvider.notifier).setNote(_orderNoteController.text.trim());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _orderNoteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<MultiCartState>(multiCartProvider, (prev, next) {
      if (prev?.activeTabId != next.activeTabId) {
        if (_orderNoteController.text != next.activeTab.note) {
          _orderNoteController.text = next.activeTab.note;
        }
      }
    });

    final cart = ref.watch(cartProvider);
    final totalAmount = ref.watch(cartTotalAmountProvider);
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Column(
          children: [
            Text(l10n.orders,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            Text(
              ref.watch(posBranchNameProvider),
              style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.normal),
            ),
          ],
        ),
        centerTitle: true,
        backgroundColor: AppColors.white,
      ),
      body: _isSaving
          ? const Center(child: LoadingIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Thanh tìm kiếm sản phẩm nhanh (KiotViet style)
                  _buildProductSearchBar(context, cart, currencyFormat),
                  const SizedBox(height: 12),

                  // 1. Chọn Khách Hàng
                  _buildCustomerSelectorCard(context),
                  const SizedBox(height: 12),

                  // 2. Danh sách sản phẩm mua
                  _buildOrderItemsCard(context, cart, currencyFormat),
                  const SizedBox(height: 12),

                  // 3. Ghi chú đơn hàng tổng (KiotViet style)
                  _buildOrderNoteCard(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomActionsBar(
        context,
        totalAmount,
        cart,
      ),
    );
  }

  // Quét hoặc nhập nhanh mã vạch sản phẩm
  Future<void> _scanOrInputBarcode(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final barcodeController = TextEditingController();
    final scanned = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_scanner, color: AppColors.primary),
            const SizedBox(width: 8),
            Text(l10n?.posScanBarcode ?? 'Quét mã vạch',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n?.posScanBarcodePrompt ??
                  'Nhập hoặc quét mã vạch sản phẩm để thêm nhanh vào đơn:',
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: barcodeController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: l10n?.posBarcodeLabel ?? 'Mã vạch (Barcode)',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.qr_code),
              ),
              onSubmitted: (val) => Navigator.pop(dialogCtx, val.trim()),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: Text(l10n?.cancel ?? 'Hủy'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogCtx, barcodeController.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(l10n?.posFindAndAdd ?? 'Tìm & Thêm'),
          ),
        ],
      ),
    );

    if (scanned != null && scanned.isNotEmpty) {
      if (!context.mounted) return;
      final allProducts = ref.read(productListProvider).valueOrNull ?? [];
      final code = scanned.toLowerCase();
      final matches = allProducts.where(
        (p) =>
            (p.barcode != null && p.barcode!.toLowerCase() == code) ||
            p.code.toLowerCase() == code,
      );

      if (matches.isNotEmpty) {
        final matched = matches.first;
        ref.read(cartProvider.notifier).addToCart(matched);
        HapticFeedback.lightImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.posItemAddedSuccess(matched.name) ??
                  'Đã thêm: ${matched.name}',
            ),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 2),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              l10n?.posBarcodeNotFound(scanned) ??
                  'Không tìm thấy sản phẩm có mã vạch: $scanned',
            ),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    }
  }

  // Thanh tìm kiếm sản phẩm nhanh (KiotViet style)
  Widget _buildProductSearchBar(
    BuildContext context,
    Map<String, CartItem> cart,
    NumberFormat format,
  ) {
    final allProducts = ref.watch(productListProvider).valueOrNull ?? [];
    final selectedBranch = ref.watch(selectedPOSBranchProvider);

    final List<Product> searchResults;
    if (_searchQuery.isEmpty) {
      searchResults = const [];
    } else {
      final q = _searchQuery.toLowerCase();
      searchResults = allProducts.where((p) {
        if (!p.allowSale) return false;
        return p.name.toLowerCase().contains(q) ||
            p.code.toLowerCase().contains(q) ||
            (p.barcode != null && p.barcode!.toLowerCase().contains(q)) ||
            p.category.toLowerCase().contains(q);
      }).toList();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Thanh ô tìm kiếm + Nút Thêm mới + Nút Barcode
        Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    hintText: 'Tên, mã hàng, mã vạch...',
                    hintStyle: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: AppColors.textSecondary,
                      size: 22,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear,
                                size: 18, color: AppColors.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 14),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (query) {
                    if (searchResults.length == 1) {
                      ref
                          .read(cartProvider.notifier)
                          .addToCart(searchResults.first);
                      HapticFeedback.lightImpact();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Đã thêm: ${searchResults.first.name}'),
                          duration: const Duration(seconds: 1),
                          backgroundColor: AppColors.success,
                        ),
                      );
                      _searchController.clear();
                      _searchFocusNode.unfocus();
                    }
                  },
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Nút Thêm hàng hóa mới (+)
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: IconButton(
                icon: const Icon(Icons.add, color: AppColors.textPrimary),
                tooltip: 'Thêm hàng hóa mới',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const AddProductPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 8),
            // Nút Quét Barcode
            Container(
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: IconButton(
                icon: const Icon(Icons.qr_code_scanner,
                    color: AppColors.textPrimary),
                tooltip: 'Quét mã vạch',
                onPressed: () => _scanOrInputBarcode(context),
              ),
            ),
          ],
        ),

        // Danh sách kết quả tìm kiếm live
        if (_searchQuery.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.black.withOpacity(0.06),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            constraints: const BoxConstraints(maxHeight: 280),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Kết quả tìm kiếm (${searchResults.length})',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _searchController.clear();
                          _searchFocusNode.unfocus();
                        },
                        child: const Text(
                          'Đóng',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1, color: AppColors.borderLight),
                if (searchResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Không tìm thấy sản phẩm phù hợp',
                      style: TextStyle(
                          fontSize: 13, color: AppColors.textSecondary),
                    ),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: searchResults.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 1, color: AppColors.borderLight),
                      itemBuilder: (ctx, idx) {
                        final p = searchResults[idx];
                        final stock = ComboHelper.getAvailableStock(
                          product: p,
                          branchId: selectedBranch,
                          allProducts: allProducts,
                        );
                        final inCart = cart[p.id];

                        return InkWell(
                          onTap: () {
                            ref.read(cartProvider.notifier).addToCart(p);
                            HapticFeedback.lightImpact();
                            ScaffoldMessenger.of(context).hideCurrentSnackBar();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Đã thêm: ${p.name}'),
                                duration: const Duration(seconds: 1),
                                backgroundColor: AppColors.success,
                              ),
                            );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                ProductImageThumbnail(
                                  imageUrl: p.primaryImageUrl ?? p.imageUrl,
                                  productName: p.name,
                                  categoryName: p.category,
                                  size: 40,
                                  borderRadius: 6,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        p.name,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          if (p.code.isNotEmpty) ...[
                                            Text(
                                              p.code,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.textSecondary,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            const Text('•',
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: AppColors.textMuted)),
                                            const SizedBox(width: 6),
                                          ],
                                          Text(
                                            stock > 0
                                                ? 'Tồn: $stock'
                                                : 'Hết hàng',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: stock > 0
                                                  ? AppColors.textSecondary
                                                  : AppColors.danger,
                                              fontWeight: stock > 0
                                                  ? FontWeight.normal
                                                  : FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(
                                      '${format.format(p.price)} đ',
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    if (inCart != null)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary
                                              .withOpacity(0.1),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          'Trong đơn: ${inCart.quantity} +',
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      )
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: AppColors.primary,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                        ),
                                        child: const Text(
                                          '+ Thêm',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.white,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // Bottom sheet chi tiết món hàng: Giảm giá & Ghi chú trên từng món (Chuẩn KiotViet)
  void _showEditItemSheet(BuildContext context, CartItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => _EditCartItemSheet(item: item),
    );
  }

  // 1. Card chọn khách hàng
  Widget _buildCustomerSelectorCard(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return InkWell(
      onTap: () => showCustomerSelectionSheet(
        context: context,
        onCustomerSelected: (cust) {
          setState(() => _selectedCustomer = cust);
        },
      ),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.person_outline,
                color: AppColors.textSecondary, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedCustomer?.name ?? l10n.retailCustomer,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            if (_selectedCustomer != null &&
                _selectedCustomer!.displayCurrentDebt > 0)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Text(
                  'Nợ: ${NumberFormat('#,###', 'vi_VN').format(_selectedCustomer!.displayCurrentDebt)}đ',
                  style: const TextStyle(
                    color: AppColors.danger,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            const Icon(Icons.chevron_right,
                color: AppColors.textSecondary, size: 20),
          ],
        ),
      ),
    );
  }

  // 2. Card danh sách sản phẩm
  Widget _buildOrderItemsCard(
      BuildContext context, Map<String, CartItem> cart, NumberFormat format) {
    final selectedBranch = ref.watch(selectedPOSBranchProvider);
    final allProducts = ref.watch(productListProvider).valueOrNull ?? [];

    if (cart.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(24),
        alignment: Alignment.center,
        child: Text(
          AppLocalizations.of(context)?.posCartEmpty ?? 'Giỏ hàng đang trống',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: cart.length,
        separatorBuilder: (_, __) =>
            const Divider(height: 20, color: AppColors.borderLight),
        itemBuilder: (context, index) {
          final item = cart.values.elementAt(index);
          final catalogProduct = allProducts.firstWhere(
            (p) => p.id == item.product.id,
            orElse: () => item.product,
          );
          final availableStock = ComboHelper.getAvailableStock(
            product: catalogProduct,
            branchId: selectedBranch,
            allProducts: allProducts,
          );
          final bool isOutOfStock = availableStock <= 0;
          final bool isInsufficient = item.quantity > availableStock;

          return Dismissible(
            key: Key('dismissible_cart_item_${item.product.id}'),
            direction: DismissDirection.horizontal,
            background: Container(
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline,
                color: AppColors.white,
                size: 24,
              ),
            ),
            secondaryBackground: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: AppColors.danger,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.delete_outline,
                color: AppColors.white,
                size: 24,
              ),
            ),
            onDismissed: (direction) {
              final removedItem = item;
              final currentTabId = ref.read(multiCartProvider).activeTabId;
              final cartNotifier = ref.read(cartProvider.notifier);
              cartNotifier.removeFromCart(item.product.id);

              final messenger = ScaffoldMessenger.of(context);
              messenger.hideCurrentSnackBar();
              messenger.showSnackBar(
                SnackBar(
                  content: Text(
                    AppLocalizations.of(context)?.posItemRemovedFromCart(
                            removedItem.product.name) ??
                        'Đã xóa "${removedItem.product.name}" khỏi giỏ hàng',
                  ),
                  duration: const Duration(seconds: 4),
                  action: SnackBarAction(
                    label: AppLocalizations.of(context)?.commonUndo ?? 'Hoàn tác',
                    textColor: AppColors.white,
                    onPressed: () {
                      cartNotifier.restoreCartItem(
                        removedItem,
                        tabId: currentTabId,
                      );
                    },
                  ),
                ),
              );
            },
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
              InkWell(
                onTap: () => _showEditItemSheet(context, item),
                child: ProductImageThumbnail(
                  imageUrl: item.product.primaryImageUrl ??
                      item.product.imageUrl,
                  productName: item.product.name,
                  categoryName: item.product.category,
                  size: 46,
                  borderRadius: 8,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InkWell(
                  onTap: () => _showEditItemSheet(context, item),
                  borderRadius: BorderRadius.circular(6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.product.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (item.discount > 0) ...[
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 6,
                          runSpacing: 2,
                          children: [
                            Text(
                              format.format(item.effectivePrice),
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              format.format(item.price),
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 12,
                                decoration: TextDecoration.lineThrough,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                item.isDiscountPercent
                                    ? '-${NumberFormat.compact().format(item.discount)}%'
                                    : '-${format.format(item.discount)}đ',
                                style: const TextStyle(
                                  color: Colors.red,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ] else ...[
                        Text(
                          format.format(item.price),
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      if (item.note != null &&
                          item.note!.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sticky_note_2_outlined,
                                  size: 12, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  item.note!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textSecondary,
                                    fontStyle: FontStyle.italic,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Icon(Icons.edit_note,
                              size: 13,
                              color: AppColors.primary.withOpacity(0.8)),
                          const SizedBox(width: 2),
                          Flexible(
                            child: Text(
                              item.discount > 0 ||
                                      (item.note != null && item.note!.isNotEmpty)
                                  ? 'Chạm để sửa giảm giá / ghi chú'
                                  : 'Giảm giá / Ghi chú món',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.primary.withOpacity(0.8),
                                fontWeight: FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (isOutOfStock) ...[
                        const SizedBox(height: 2),
                        const Text(
                          'Hết hàng tại chi nhánh này',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ] else if (isInsufficient) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Không đủ hàng (Tồn: $availableStock, Cần: ${item.quantity})',
                          style: const TextStyle(
                            color: AppColors.warning,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                      if (item.product.isCombo &&
                          item.product.comboComponents.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Gồm: ${item.product.comboComponents.map((c) => "${c.quantity * item.quantity}x ${c.productName}").join(", ")}',
                          style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Bộ tăng giảm số lượng Stepper [-] [1] [+] chuẩn KiotViet
              Container(
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    InkWell(
                      onTap: () {
                        ref
                            .read(cartProvider.notifier)
                            .decreaseQuantity(item.product.id);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Icon(Icons.remove,
                            size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                    Container(
                      constraints: const BoxConstraints(minWidth: 26),
                      alignment: Alignment.center,
                      child: Text(
                        '${item.quantity}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                    InkWell(
                      onTap: () {
                        ref
                            .read(cartProvider.notifier)
                            .increaseQuantity(item.product.id);
                      },
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        child: Icon(Icons.add,
                            size: 16, color: AppColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
      ),
    );
  }

  // 3. Card ghi chú đơn hàng tổng (KiotViet style)
  Widget _buildOrderNoteCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.notes_rounded,
                  size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 8),
              Text(
                AppLocalizations.of(context)?.posOrderNoteTitle ??
                    'Ghi chú đơn hàng',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _orderNoteController,
            maxLines: 3,
            minLines: 2,
            inputFormatters: [
              LengthLimitingTextInputFormatter(500),
            ],
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)?.posOrderNoteHint ??
                  'Nhập ghi chú cho đơn hàng (nếu có)...',
              hintStyle: const TextStyle(fontSize: 13, color: AppColors.textMuted),
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.borderLight),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 4. Thanh hành động dưới cùng
  Widget _buildBottomActionsBar(
    BuildContext context,
    double totalAmount,
    Map<String, CartItem> cart,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final totalItemsCount =
        cart.values.fold<int>(0, (sum, i) => sum + i.quantity);

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text(
                      'Tổng tiền hàng',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.3)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$totalItemsCount',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${currencyFormat.format(totalAmount)} đ',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                // Nút Lưu tạm
                Expanded(
                  flex: 1,
                  child: OutlinedButton(
                    onPressed: cart.isEmpty || _isSaving
                        ? null
                        : () => _confirmSaveDraft(
                              context,
                              totalAmount,
                              cart,
                            ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.saveDraft,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Nút Thanh toán
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    onPressed: cart.isEmpty || _isSaving
                        ? null
                        : () async {
                            final activeTab =
                                ref.read(multiCartProvider).activeTab;
                            final effDiscount = activeTab.discount > 0
                                ? activeTab.discount
                                : widget.initialDiscount;
                            final effIsPercent = activeTab.discount > 0
                                ? activeTab.isDiscountPercent
                                : widget.isDiscountPercent;
                            final updatedCustomer =
                                await Navigator.of(context).push<Customer?>(
                              MaterialPageRoute(
                                builder: (context) => POSPaymentPage(
                                  initialCustomer: _selectedCustomer,
                                  initialDiscount: effDiscount,
                                  isDiscountPercent: effIsPercent,
                                  initialNote: _orderNoteController.text.trim().isNotEmpty
                                      ? _orderNoteController.text.trim()
                                      : widget.initialNote,
                                ),
                              ),
                            );
                            if (mounted && updatedCustomer != null) {
                              setState(() => _selectedCustomer = updatedCustomer);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(
                      l10n.checkout,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Popup xác nhận Lưu tạm đơn hàng nháp
  void _confirmSaveDraft(
    BuildContext context,
    double totalAmount,
    Map<String, CartItem> cart,
  ) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          title: Text(l10n.saveDraftTitle),
          content: Text(l10n.saveDraftConfirm),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(l10n.no),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(dialogCtx);
                await _submitDraftOrder(totalAmount, cart);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: Text(l10n.saveDraft),
            )
          ],
        );
      },
    );
  }

  // Submit đơn nháp
  Future<void> _submitDraftOrder(
    double totalAmount,
    Map<String, CartItem> cart,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (cart.isEmpty) return;
    setState(() => _isSaving = true);

    try {
      final now = DateTime.now();
      final selectedBranch = ref.read(selectedPOSBranchProvider);
      final activeOrderId = ref.read(activeOrderIdProvider);
      final String id;
      if (activeOrderId != null &&
          activeOrderId.isNotEmpty &&
          !activeOrderId.contains('.')) {
        id = activeOrderId;
      } else {
        final originalOrder = ref.read(editingOriginalOrderProvider);
        if (originalOrder != null) {
          id = await OrderCodeResolver.resolveVersionedOrderCode(
            ref,
            originalOrderId: originalOrder.id,
            storeId: selectedBranch,
          );
        } else {
          id = await OrderCodeResolver.resolveNextOrderCode(ref,
              storeId: selectedBranch);
        }
      }

      final List<OrderItem> orderItems = cart.values.map((item) {
        return OrderItem(
          productId: item.product.id,
          productName: item.product.name,
          quantity: item.quantity,
          price: item.effectivePrice,
          originalPrice: item.price,
          discount: item.discount,
          isDiscountPercent: item.isDiscountPercent,
          note: item.note,
          warrantyMonths: 12,
          purchaseDate: now,
        );
      }).toList();

      final customerId = _selectedCustomer?.id ?? 'khach_le';
      final currentUser = ref.read(authProvider);
      final originalOrder = ref.read(editingOriginalOrderProvider);

      final activeTab = ref.read(multiCartProvider).activeTab;
      final orderDiscount =
          activeTab.discount > 0 ? activeTab.discount : widget.initialDiscount;
      final isPercent = activeTab.discount > 0
          ? activeTab.isDiscountPercent
          : widget.isDiscountPercent;
      final double finalDiscountAmount;
      if (isPercent) {
        finalDiscountAmount =
            (totalAmount * orderDiscount / 100).clamp(0.0, totalAmount);
      } else {
        finalDiscountAmount = orderDiscount.clamp(0.0, totalAmount);
      }

      final String? resolvedCustomerPhone;
      if (_selectedCustomer?.phone != null &&
          _selectedCustomer!.phone.trim().isNotEmpty) {
        resolvedCustomerPhone = _selectedCustomer!.phone.trim();
      } else if (_selectedCustomer == null ||
          _selectedCustomer!.id == originalOrder?.customerId) {
        resolvedCustomerPhone = originalOrder?.customerPhone;
      } else {
        resolvedCustomerPhone = null;
      }

      final order = Order(
        id: id,
        customerId: customerId,
        customerName: _selectedCustomer?.name,
        customerPhone: resolvedCustomerPhone,
        createdAt: now,
        items: orderItems,
        total: totalAmount,
        discount: finalDiscountAmount,
        status: 'draft',
        amountPaid: 0.0,
        debtAmount: 0.0,
        paymentMethod: 'cash',
        createdBy: currentUser?.username,
        createdByName: currentUser?.name,
        storeId: selectedBranch,
        cashAmount: null,
        transferAmount: null,
        note: _orderNoteController.text.trim().isNotEmpty
            ? _orderNoteController.text.trim()
            : null,
      );

      await ref.read(orderRepositoryProvider).create(order);

      // Nếu đang chỉnh sửa hóa đơn gốc (replacement), cập nhật trạng thái hủy cho đơn cũ SAU KHI tạo đơn mới thành công
      if (originalOrder != null && !originalOrder.isCancelled) {
        try {
          final cancelUseCase = ref.read(cancelInvoiceUseCaseProvider);
          await cancelUseCase.execute(
            order: originalOrder,
            cancelReason: 'Đã sửa thành $id',
            currentUser: currentUser ??
                UserAccount(
                  username: 'system',
                  displayName: 'Hệ thống',
                  role: 'admin',
                  storeId: selectedBranch,
                ),
            storeId: originalOrder.storeId ?? selectedBranch,
            isReplacement: true,
          );
        } catch (cancelErr) {
          debugPrint('Warning: Could not cancel replaced order when saving draft: $cancelErr');
        }
      }

      ref.read(cartProvider.notifier).clearCart();
      ref.read(activeOrderIdProvider.notifier).state = null;
      ref.read(editingOriginalOrderProvider.notifier).state = null;
      _orderNoteController.clear();
      ref.read(multiCartProvider.notifier).setNote('');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.draftSaved),
          backgroundColor: AppColors.success,
        ),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi: $e')),
        );
      }
    }
  }
}

/// Modal Bottom Sheet chỉnh sửa chi tiết món hàng (Giảm giá, số lượng, ghi chú từng món)
class _EditCartItemSheet extends ConsumerStatefulWidget {
  final CartItem item;

  const _EditCartItemSheet({required this.item});

  @override
  ConsumerState<_EditCartItemSheet> createState() => _EditCartItemSheetState();
}

class _EditCartItemSheetState extends ConsumerState<_EditCartItemSheet> {
  late int _currentQty;
  late bool _isPercent;
  late final TextEditingController _discountController;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _currentQty = widget.item.quantity;
    _isPercent = widget.item.isDiscountPercent;

    final discountStr = widget.item.discount > 0
        ? (_isPercent
            ? (widget.item.discount == widget.item.discount.roundToDouble()
                ? widget.item.discount.toInt().toString()
                : widget.item.discount.toString())
            : NumberFormat('#,###', 'vi_VN').format(widget.item.discount))
        : '';
    _discountController = TextEditingController(text: discountStr);
    _noteController = TextEditingController(text: widget.item.note ?? '');
  }

  @override
  void dispose() {
    _discountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final format = NumberFormat('#,###', 'vi_VN');
    final allProducts = ref.read(productListProvider).valueOrNull ?? [];
    final selectedBranch = ref.read(selectedPOSBranchProvider);
    final catalogProduct = allProducts.firstWhere(
      (p) => p.id == widget.item.product.id,
      orElse: () => widget.item.product,
    );
    final availableStock = ComboHelper.getAvailableStock(
      product: catalogProduct,
      branchId: selectedBranch,
      allProducts: allProducts,
    );

    double parsedDiscount = 0.0;
    final rawDiscount = _discountController.text
        .replaceAll('.', '')
        .replaceAll(',', '')
        .trim();
    parsedDiscount = double.tryParse(rawDiscount) ?? 0.0;

    final unitBasePrice = widget.item.price;
    final double unitDiscountAmount;
    if (parsedDiscount <= 0) {
      unitDiscountAmount = 0.0;
    } else if (_isPercent) {
      unitDiscountAmount =
          (unitBasePrice * parsedDiscount / 100).clamp(0.0, unitBasePrice);
    } else {
      unitDiscountAmount = parsedDiscount.clamp(0.0, unitBasePrice);
    }
    final unitEffectivePrice =
        (unitBasePrice - unitDiscountAmount).clamp(0.0, double.infinity);
    final lineTotal = unitEffectivePrice * _currentQty;

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = MediaQuery.of(context).size.height - bottomInset;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: (availableHeight * 0.9).clamp(200.0, double.infinity),
        ),
        decoration: const BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              const SizedBox(height: 8),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Top Bar: Nút Back & Nút Xóa
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_ios_new,
                          size: 20, color: AppColors.textPrimary),
                      onPressed: () => Navigator.pop(context),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline,
                          size: 22, color: AppColors.danger),
                      tooltip: l10n?.posRemoveFromCart ?? 'Xóa khỏi đơn',
                      onPressed: () {
                        ref
                            .read(cartProvider.notifier)
                            .removeFromCart(widget.item.product.id);
                        Navigator.pop(context);
                      },
                    ),
                  ],
                ),
              ),

              // Nội dung cuộn được
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header thông tin sản phẩm: Ảnh + Tên đầy đủ xuống dòng + Mã + Tồn + Giá
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ProductImageThumbnail(
                            imageUrl: widget.item.product.primaryImageUrl ??
                                widget.item.product.imageUrl,
                            productName: widget.item.product.name,
                            categoryName: widget.item.product.category,
                            size: 68,
                            borderRadius: 12,
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.item.product.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                    color: AppColors.textPrimary,
                                    height: 1.25,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (widget.item.product.code.isNotEmpty) ...[
                                      Text(
                                        widget.item.product.code,
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w500,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                    ],
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        l10n?.posStockCountLabel(
                                                availableStock) ??
                                            'Tồn: $availableStock',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: availableStock > 0
                                              ? AppColors.textSecondary
                                              : AppColors.danger,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  '${format.format(unitBasePrice)} đ',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(height: 1, color: Color(0xFFF1F5F9)),
                      const SizedBox(height: 10),

                      // Row 1: Số lượng
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n?.quantity ?? 'Số lượng',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  InkWell(
                                    onTap: () {
                                      if (_currentQty > 1) {
                                        setState(() => _currentQty--);
                                      }
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 6),
                                      child: Icon(Icons.remove,
                                          size: 18,
                                          color: AppColors.textSecondary),
                                    ),
                                  ),
                                  Container(
                                    constraints:
                                        const BoxConstraints(minWidth: 32),
                                    alignment: Alignment.center,
                                    child: Text(
                                      '$_currentQty',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 15),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () {
                                      setState(() => _currentQty++);
                                    },
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 6),
                                      child: Icon(Icons.add,
                                          size: 18,
                                          color: AppColors.textSecondary),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Row 2: Đơn giá gốc
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n?.unitPrice ?? 'Đơn giá',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.only(bottom: 4),
                              decoration: const BoxDecoration(
                                border: Border(
                                    bottom:
                                        BorderSide(color: Color(0xFFE2E8F0))),
                              ),
                              child: Text(
                                '${format.format(unitBasePrice)} đ',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Row 3: Giảm giá (có toggle % / VNĐ)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      _isPercent
                                          ? (l10n?.posDiscountPercent ??
                                              'Giảm giá (%)')
                                          : (l10n?.posDiscountAmount ??
                                              'Giảm giá (đ)'),
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        InkWell(
                                          onTap: () {
                                            if (!_isPercent) {
                                              setState(() {
                                                _isPercent = true;
                                                _discountController.clear();
                                              });
                                            }
                                          },
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: _isPercent
                                                  ? AppColors.primary
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              '%',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: _isPercent
                                                    ? Colors.white
                                                    : AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                        InkWell(
                                          onTap: () {
                                            if (_isPercent) {
                                              setState(() {
                                                _isPercent = false;
                                                _discountController.clear();
                                              });
                                            }
                                          },
                                          borderRadius:
                                              BorderRadius.circular(6),
                                          child: Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: !_isPercent
                                                  ? AppColors.primary
                                                  : Colors.transparent,
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              'đ',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: !_isPercent
                                                    ? Colors.white
                                                    : AppColors.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 100,
                              child: TextField(
                                controller: _discountController,
                                textAlign: TextAlign.right,
                                keyboardType: TextInputType.number,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: '0',
                                  hintStyle: TextStyle(
                                      fontSize: 15,
                                      color: AppColors.textMuted),
                                  contentPadding:
                                      EdgeInsets.only(bottom: 4),
                                  border: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color: Color(0xFFE2E8F0)),
                                  ),
                                  enabledBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color: Color(0xFFE2E8F0)),
                                  ),
                                  focusedBorder: UnderlineInputBorder(
                                    borderSide: BorderSide(
                                        color: AppColors.primary,
                                        width: 1.5),
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Quick chips giảm giá nhanh
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: (_isPercent
                                    ? [5, 10, 15, 20, 30]
                                    : [
                                        10000,
                                        20000,
                                        50000,
                                        100000,
                                        200000
                                      ])
                                .map((val) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: ActionChip(
                                  label: Text(
                                    _isPercent
                                        ? '$val%'
                                        : '${format.format(val)}đ',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 0),
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() {
                                      _discountController.text = _isPercent
                                          ? val.toString()
                                          : NumberFormat(
                                                  '#,###', 'vi_VN')
                                              .format(val);
                                    });
                                  },
                                ),
                              );
                            }).toList()
                              ..add(
                                Padding(
                                  padding:
                                      const EdgeInsets.only(right: 6),
                                  child: ActionChip(
                                    label: Text(
                                      l10n?.posClearDiscount ?? 'Bỏ giảm',
                                      style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.danger),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 4, vertical: 0),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () {
                                      setState(() {
                                        _discountController.clear();
                                      });
                                    },
                                  ),
                                ),
                              ),
                          ),
                        ),
                      ),

                      // Row 4: Giá bán (sau khi giảm)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n?.posSellingPrice ?? 'Giá bán',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.only(bottom: 4),
                              decoration: const BoxDecoration(
                                border: Border(
                                    bottom: BorderSide(
                                        color: Color(0xFFE2E8F0))),
                              ),
                              child: Text(
                                '${format.format(unitEffectivePrice)} đ',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Row 5: Thành tiền
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              l10n?.amount ?? 'Thành tiền',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Text(
                              '${format.format(lineTotal)} đ',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Ô ghi chú trên từng món hàng (chuẩn KiotViet)
                      TextField(
                        controller: _noteController,
                        minLines: 2,
                        maxLines: 4,
                        inputFormatters: [
                          LengthLimitingTextInputFormatter(300),
                        ],
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: l10n?.posItemNoteHint ??
                              'Nhập ghi chú (tối đa 300 ký tự)',
                          hintStyle: const TextStyle(
                            fontSize: 14,
                            color: AppColors.textMuted,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF4F6F8),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Nút Xong (Full-width KiotViet Blue)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, -2),
                    )
                  ],
                ),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0070F0),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: () {
                      final finalNote = _noteController.text.trim();
                      ref.read(cartProvider.notifier).updateItemDetails(
                            widget.item.product.id,
                            discount: parsedDiscount,
                            isDiscountPercent: _isPercent,
                            note: finalNote.isEmpty ? null : finalNote,
                            clearNote: finalNote.isEmpty,
                          );
                      if (_currentQty != widget.item.quantity) {
                        ref.read(cartProvider.notifier).updateQuantity(
                            widget.item.product.id, _currentQty);
                      }
                      Navigator.pop(context);
                    },
                    child: const Text(
                      'Xong',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bottom Sheet chọn khách hàng dùng chung
Future<void> showCustomerSelectionSheet({
  required BuildContext context,
  required ValueChanged<Customer?> onCustomerSelected,
}) async {
  final l10n = AppLocalizations.of(context)!;
  final result = await showModalBottomSheet<dynamic>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.only(
        topLeft: Radius.circular(16),
        topRight: Radius.circular(16),
      ),
    ),
    builder: (bottomSheetContext) {
      String searchQuery = '';
      return StatefulBuilder(
        builder: (modalContext, setModalState) {
          return Consumer(
            builder: (consumerContext, ref, child) {
              final customersAsync = ref.watch(customerListNotifierProvider);
              return Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(consumerContext).size.height * 0.8,
                ),
                padding: EdgeInsets.only(
                  top: 16,
                  bottom: MediaQuery.of(consumerContext).viewInsets.bottom + 24,
                  left: 16,
                  right: 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          l10n.selectCustomer,
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline,
                              color: AppColors.primary, size: 28),
                          onPressed: () {
                            Navigator.pop(bottomSheetContext, 'ADD_NEW');
                          },
                        )
                      ],
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      decoration: InputDecoration(
                        hintText: l10n.searchCustomersHint,
                        prefixIcon: const Icon(Icons.search, size: 20),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: const BorderSide(color: AppColors.border),
                        ),
                      ),
                      onChanged: (v) {
                        setModalState(() {
                          searchQuery = v.trim().toLowerCase();
                        });
                      },
                    ),
                    const SizedBox(height: 8),
                    const Divider(color: AppColors.divider),
                    customersAsync.when(
                      data: (customers) {
                        final filteredCustomers = searchQuery.isEmpty
                            ? customers
                            : customers
                                .where((c) =>
                                    c.name
                                        .toLowerCase()
                                        .contains(searchQuery) ||
                                    c.phone
                                        .toLowerCase()
                                        .contains(searchQuery) ||
                                    c.address
                                        .toLowerCase()
                                        .contains(searchQuery))
                                .toList();

                        return Flexible(
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: filteredCustomers.length +
                                (searchQuery.isEmpty ? 1 : 0),
                            itemBuilder: (ctx, idx) {
                              if (searchQuery.isEmpty && idx == 0) {
                                return ListTile(
                                  title: Text(l10n.retailCustomer,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold)),
                                  onTap: () {
                                    onCustomerSelected(null);
                                    Navigator.pop(bottomSheetContext);
                                  },
                                );
                              }
                              final customer = searchQuery.isEmpty
                                  ? filteredCustomers[idx - 1]
                                  : filteredCustomers[idx];
                              return ListTile(
                                title: Text(customer.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                    '${customer.phone} • ${customer.address}'),
                                trailing: (customer.displayCurrentDebt > 0)
                                    ? Text(
                                        'Nợ: ${NumberFormat('#,###', 'vi_VN').format(customer.displayCurrentDebt)}đ',
                                        style: const TextStyle(
                                          color: AppColors.danger,
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      )
                                    : null,
                                onTap: () {
                                  onCustomerSelected(customer);
                                  Navigator.pop(bottomSheetContext);
                                },
                              );
                            },
                          ),
                        );
                      },
                      loading: () => const Center(child: LoadingIndicator()),
                      error: (e, _) =>
                          Center(child: Text('${l10n.notFound}: $e')),
                    )
                  ],
                ),
              );
            },
          );
        },
      );
    },
  );

  if (!context.mounted) return;
  if (result == 'ADD_NEW') {
    final newCust = await showDialog<Customer>(
      context: context,
      builder: (dialogContext) => const AddCustomerDialog(),
    );
    if (newCust != null && context.mounted) {
      onCustomerSelected(newCust);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.addCustomerSuccess),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }
}

/// Hộp thoại Popup thêm mới khách hàng inline trực tiếp
class AddCustomerDialog extends ConsumerStatefulWidget {
  const AddCustomerDialog({super.key});

  @override
  ConsumerState<AddCustomerDialog> createState() => _AddCustomerDialogState();
}

class _AddCustomerDialogState extends ConsumerState<AddCustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _noteController = TextEditingController();
  bool _isSaving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    try {
      final currentUser = ref.read(authProvider);
      final activeBranchName =
          await ref.read(currentStoreNameProvider.future);

      final existingCusts =
          ref.read(customerListNotifierProvider).value ?? [];
      final custIds = existingCusts.map((c) => c.id).toList();
      final newCustId = CodeGeneratorHelper.generateNextCustomerCode(custIds);

      final newCust = Customer(
        id: newCustId,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        notes: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
        purchases: const [],
        branch: activeBranchName,
        createdAt: DateTime.now().toIso8601String(),
        createdBy: currentUser?.username ?? 'admin',
        status: '1',
      );

      await ref.read(customerRepositoryProvider).upsert(newCust);
      // Danh sách khách hàng là realtime, không cần invalidate (tránh tải lại toàn bộ).

      final currentStoreId = ref.read(currentStoreIdProvider);
      try {
        await ref.read(notificationDispatcherProvider).notifyCustomerCreated(
              storeId: currentStoreId.isNotEmpty ? currentStoreId : 'store_001',
              customer: newCust,
              user: currentUser,
            );
      } catch (notifErr) {
        debugPrint(
            'Warning: Could not dispatch customer created notification: $notifErr');
      }

      if (!mounted) return;
      Navigator.of(context).pop(newCust);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(
        l10n.addNewCustomer,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: l10n.fullNameRequired,
                  border: const OutlineInputBorder(),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? l10n.pleaseEnterName : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: InputDecoration(
                  labelText: l10n.phoneNumberRequired,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.isEmpty) {
                    return '${l10n.pleaseEnter} ${l10n.phone}';
                  }
                  final vnPhoneRegex = RegExp(r'^(03|05|07|08|09)\d{8}$');
                  if (!vnPhoneRegex.hasMatch(text)) {
                    return l10n.pleaseEnterValidNumber;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: l10n.email,
                  border: const OutlineInputBorder(),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  final text = v?.trim() ?? '';
                  if (text.isNotEmpty) {
                    final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
                    if (!emailRegex.hasMatch(text)) {
                      return l10n.pleaseEnterValidEmail;
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: InputDecoration(
                  labelText: l10n.address,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                decoration: InputDecoration(
                  labelText: l10n.note,
                  border: const OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _save,
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.white,
                  ),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }
}
