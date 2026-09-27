import 'package:stores/core/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventories/stock_in_receipts_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/suppliers/suppliers_providers.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/supplier.dart';
import '../../suppliers/pages/add_edit_supplier_page.dart';
import '../widgets/sticky_bottom_summary_bar.dart';
import '../widgets/stock_in_exit_dialog.dart';
import '../widgets/stock_in_item_card.dart';
import '../widgets/stock_in_payment_confirmation_view.dart';
import '../widgets/stock_in_product_edit_sheet.dart';

/// 2-Step Modern Import Inventory Page matching KiotViet standard and video DATA_IMPORT/video_2026-09-27_07-41-44.mp4.
///
/// Flow:
/// - Step 1: Product Selection & Cart
///   * Top bar with Close (X) button, title ("Phiếu nhập hàng mới" or resuming draft code), and branch info badge.
///   * Supplier selector card, product search field with barcode scan button, and category filters.
///   * Selecting a product opens [StockInProductEditSheet] (pre-filled with latest historical import price).
///   * Empty state illustration ("Chưa có hàng trong phiếu") or ListView of [StockInItemCard]s.
///   * Pinned [StickyBottomSummaryBar] with "Lưu tạm" and "Tiếp tục".
/// - Step 2: Payment & Supplier Confirmation (when "Tiếp tục" tapped):
///   * Displays [StockInPaymentConfirmationView] with "Xem hàng trong phiếu >", financial lines, payment methods, debt toggle, note, "Lưu tạm", and "Hoàn thành".
///   * Tapping "Hoàn thành" calls [CompleteStockInReceiptUseCase] with atomic updates and pops.
/// - PopScope & Exit Handling:
///   * Intercepts back and close actions with [StockInExitDialog] ("Lưu tạm", "Rời khỏi", "Ở lại") if cart has items.
class ImportInventoryPage extends ConsumerStatefulWidget {
  final StockInReceipt? initialReceipt;

  const ImportInventoryPage({super.key, this.initialReceipt});

  @override
  ConsumerState<ImportInventoryPage> createState() =>
      _ImportInventoryPageState();
}

class _ImportInventoryPageState extends ConsumerState<ImportInventoryPage> {
  int _currentStep =
      0; // 0 = Cart & Product Selection, 1 = Payment & Supplier Confirmation
  late String _receiptId;
  late String _importCode;
  final List<StockInReceiptItem> _items = [];
  Supplier? _selectedSupplier;
  double _discount = 0.0;
  double _paidAmount = 0.0;
  bool _hasUserEditedPaidAmount = false;
  String _paymentMethod = 'cash';
  String _note = '';
  String? _selectedCategory;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    if (widget.initialReceipt != null) {
      final r = widget.initialReceipt!;
      _receiptId = r.id;
      _importCode = r.importCode;
      _items.addAll(r.items);
      _discount = r.discount;
      _paymentMethod = r.paymentMethod;
      _note = r.note;

      final net = (r.totalAmount - r.discount).clamp(0.0, double.infinity);
      // If paidAmount was not explicitly customized (e.g. paid in full or null)
      if (r.paidAmount == null ||
          (r.paidAmount != null && (r.paidAmount! - net).abs() < 1.0)) {
        _hasUserEditedPaidAmount = false;
        _paidAmount = net;
      } else {
        // User had explicitly set a custom partial payment or 0đ debt
        _hasUserEditedPaidAmount = true;
        _paidAmount = r.paidAmount!;
      }

      if (r.supplierId != null && r.supplierId!.isNotEmpty) {
        _selectedSupplier = Supplier(
          id: r.supplierId!,
          name: r.supplierName ?? 'Nhà cung cấp',
          code: '',
          phone: r.supplierPhone ?? '',
        );
      }
    } else {
      _receiptId = 'PN_${now.millisecondsSinceEpoch}';
      _importCode = 'PN_${now.millisecondsSinceEpoch}';
      _paidAmount = 0.0;
      _hasUserEditedPaidAmount = false;
    }
  }

  double get totalGoodsAmount =>
      _items.fold(0.0, (sum, item) => sum + item.totalPrice);

  int get totalQuantity => _items.fold(0, (sum, item) => sum + item.quantity);

  double get _effectivePaidAmount {
    if (_hasUserEditedPaidAmount) {
      return _paidAmount;
    }
    return (totalGoodsAmount - _discount).clamp(0.0, double.infinity);
  }

  Future<void> _handleExit() async {
    if (_items.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    final choice = await StockInExitDialog.show(context);
    if (!mounted) return;

    if (choice == StockInExitChoice.saveDraft) {
      await _saveDraft();
      if (mounted) {
        Navigator.of(context).pop();
      }
    } else if (choice == StockInExitChoice.exit) {
      Navigator.of(context).pop();
    }
    // choice == stay: do nothing, remain on page
  }

  Future<void> _saveDraft() async {
    final now = DateTime.now();
    final currentStore = ref.read(currentStoreIdProvider);
    final user = ref.read(authProvider);

    final draftReceipt = StockInReceipt(
      id: _receiptId.isNotEmpty
          ? _receiptId
          : 'PN_DRAFT_${now.millisecondsSinceEpoch}',
      importCode: _importCode.isNotEmpty
          ? _importCode
          : 'PN_${now.millisecondsSinceEpoch}',
      date: widget.initialReceipt?.date ?? now,
      storeId: currentStore,
      supplierId: _selectedSupplier?.id,
      supplierName: _selectedSupplier?.name,
      supplierPhone: _selectedSupplier?.phone,
      createdBy: user?.username,
      createdByName: user?.name,
      note: _note,
      items: _items,
      discount: _discount,
      paidAmount: _effectivePaidAmount,
      status: 'draft',
      paymentMethod: _paymentMethod,
      createdAt: widget.initialReceipt?.createdAt ?? now,
      updatedAt: now,
    );

    final saveDraftUseCase = ref.read(saveStockInDraftUseCaseProvider);
    await saveDraftUseCase.execute(draftReceipt);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã lưu phiếu tạm'),
          backgroundColor: AppColors.primaryAction,
        ),
      );
    }
  }

  Future<void> _completeReceipt({
    required String? supplierId,
    required double discount,
    required double paidAmount,
    required String paymentMethod,
    required String note,
  }) async {
    final now = DateTime.now();
    final currentStore = ref.read(currentStoreIdProvider);
    final user = ref.read(authProvider);

    final receipt = StockInReceipt(
      id: _receiptId.isNotEmpty
          ? _receiptId
          : 'PN_${now.millisecondsSinceEpoch}',
      importCode: _importCode.isNotEmpty
          ? _importCode
          : 'PN_${now.millisecondsSinceEpoch}',
      date: widget.initialReceipt?.date ?? now,
      storeId: currentStore,
      supplierId: supplierId ?? _selectedSupplier?.id,
      supplierName: _selectedSupplier?.name,
      supplierPhone: _selectedSupplier?.phone,
      createdBy: user?.username,
      createdByName: user?.name,
      note: note,
      items: _items,
      discount: discount,
      paidAmount: paidAmount,
      status: 'completed',
      paymentMethod: paymentMethod,
      createdAt: widget.initialReceipt?.createdAt ?? now,
      updatedAt: now,
    );

    final completeUseCase = ref.read(completeStockInReceiptUseCaseProvider);
    final completed = await completeUseCase.execute(receipt);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Đã hoàn thành phiếu nhập'),
          backgroundColor: AppColors.successMedium,
        ),
      );
      Navigator.of(context).pop(completed);
    }
  }

  Future<void> _openProductEditSheet(
      Product product, String currentStoreId) async {
    final existingIndex = _items.indexWhere((i) => i.productId == product.id);
    final existingItem = existingIndex >= 0 ? _items[existingIndex] : null;

    final resultItem = await StockInProductEditSheet.show(
      context: context,
      product: product,
      branchStock: product.stockInBranch(currentStoreId),
      storeId: currentStoreId,
      existingItem: existingItem,
    );

    if (resultItem != null && mounted) {
      setState(() {
        if (existingIndex >= 0) {
          _items[existingIndex] = resultItem;
        } else {
          _items.add(resultItem);
        }
        if (!_hasUserEditedPaidAmount) {
          _paidAmount =
              (totalGoodsAmount - _discount).clamp(0.0, double.infinity);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final currentStoreId = ref.watch(currentStoreIdProvider);
    final storesMap = ref.watch(availableStoresProvider).value ?? {};
    final storeName = storesMap[currentStoreId] ??
        (currentStoreId == 'store_002'
            ? 'Chi nhánh Thới Bình'
            : 'Chi nhánh Đông Thắng');
    final isStoreLocked = user?.isAdmin != true;
    final canViewCostPrice = user?.canViewCostPrice ?? false;

    final productsAsync = ref.watch(productListProvider);
    final allProducts = productsAsync.valueOrNull ?? [];
    final suppliersAsync = ref.watch(supplierListNotifierProvider);
    final allSuppliers = suppliersAsync.valueOrNull ?? [];

    // Ensure selectedSupplier entity is synced with live suppliers list
    if (_selectedSupplier != null && allSuppliers.isNotEmpty) {
      final matched =
          allSuppliers.where((s) => s.id == _selectedSupplier!.id).firstOrNull;
      if (matched != null) {
        _selectedSupplier = matched;
      }
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleExit();
      },
      child: _currentStep == 1
          ? StockInPaymentConfirmationView(
              receipt: StockInReceipt(
                id: _receiptId,
                importCode: _importCode,
                date: widget.initialReceipt?.date ?? DateTime.now(),
                storeId: currentStoreId,
                supplierId: _selectedSupplier?.id,
                supplierName: _selectedSupplier?.name,
                supplierPhone: _selectedSupplier?.phone,
                items: _items,
                totalAmount: totalGoodsAmount,
                discount: _discount,
                paidAmount: _effectivePaidAmount,
                paymentMethod: _paymentMethod,
                note: _note,
              ),
              suppliers: allSuppliers,
              onStateChanged: ({
                String? supplierId,
                double? discount,
                double? paidAmount,
                String? paymentMethod,
                String? note,
              }) {
                setState(() {
                  if (supplierId != null) {
                    _selectedSupplier = allSuppliers
                            .where((s) => s.id == supplierId)
                            .firstOrNull ??
                        _selectedSupplier;
                  }
                  if (discount != null) _discount = discount;
                  if (paidAmount != null) {
                    _paidAmount = paidAmount;
                    _hasUserEditedPaidAmount = true;
                  }
                  if (paymentMethod != null) _paymentMethod = paymentMethod;
                  if (note != null) _note = note;
                });
              },
              onViewItems: () {
                setState(() => _currentStep = 0);
              },
              onSaveDraft: _saveDraft,
              onComplete: ({
                required supplierId,
                required discount,
                required paidAmount,
                required paymentMethod,
                required note,
              }) async {
                await _completeReceipt(
                  supplierId: supplierId,
                  discount: discount,
                  paidAmount: paidAmount,
                  paymentMethod: paymentMethod,
                  note: note,
                );
              },
            )
          : Scaffold(
              appBar: AppBar(
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: _handleExit,
                ),
                title: Text(
                  widget.initialReceipt != null
                      ? 'Phiếu ${widget.initialReceipt!.importCode}'
                      : 'Phiếu nhập hàng mới',
                ),
              ),
              body: Column(
                children: [
                  // 1. Branch Store Locked Badge
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isStoreLocked
                          ? Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                          : Theme.of(context)
                              .colorScheme
                              .primaryContainer
                              .withOpacity(0.5),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isStoreLocked
                            ? Theme.of(context).colorScheme.outlineVariant
                            : Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isStoreLocked ? Icons.lock_outline : Icons.storefront,
                          size: 16,
                          color: isStoreLocked
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Chi nhánh nhập: $storeName${isStoreLocked ? ' (Cố định)' : ''}',
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: isStoreLocked
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant
                                      : Theme.of(context).colorScheme.primary,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 2. Supplier Selector Card
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _buildSupplierSelectorCard(context),
                  ),

                  // 3. Product Search with Barcode Scanner & Category Filter
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: _buildProductSearchBar(
                        context, allProducts, currentStoreId),
                  ),

                  // Category Filter Chips
                  _buildCategoryChips(allProducts),

                  // 4. Cart Items or Empty State Illustration
                  Expanded(
                    child: _items.isEmpty
                        ? _buildEmptyState(context)
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            itemCount: _items.length,
                            itemBuilder: (ctx, index) {
                              final item = _items[index];
                              final product = allProducts.firstWhere(
                                (p) => p.id == item.productId,
                                orElse: () => Product(
                                  id: item.productId,
                                  name: item.productName ?? 'Sản phẩm',
                                  code: item.productCode ?? '',
                                  price: 0,
                                  costPrice: item.unitPrice,
                                  branchStocks: const {},
                                  category: '',
                                ),
                              );
                              final currentStock =
                                  product.stockInBranch(currentStoreId);

                              return StockInItemCard(
                                item: item,
                                currentStock: currentStock,
                                isMasked: !canViewCostPrice,
                                onQuantityChanged: (newQty) {
                                  setState(() {
                                    _items[index] =
                                        item.copyWith(quantity: newQty);
                                    if (!_hasUserEditedPaidAmount) {
                                      _paidAmount =
                                          (totalGoodsAmount - _discount)
                                              .clamp(0.0, double.infinity);
                                    }
                                  });
                                },
                                onDelete: () {
                                  setState(() {
                                    _items.removeAt(index);
                                    if (!_hasUserEditedPaidAmount) {
                                      _paidAmount =
                                          (totalGoodsAmount - _discount)
                                              .clamp(0.0, double.infinity);
                                    }
                                  });
                                },
                                onTap: () => _openProductEditSheet(
                                    product, currentStoreId),
                              );
                            },
                          ),
                  ),

                  // 5. Pinned StickyBottomSummaryBar
                  StickyBottomSummaryBar(
                    totalAmount: totalGoodsAmount,
                    itemCount: _items.length,
                    totalQuantity: totalQuantity,
                    isEnabled: _items.isNotEmpty,
                    onSaveDraft: _saveDraft,
                    onContinue: () {
                      if (!_hasUserEditedPaidAmount) {
                        _paidAmount = (totalGoodsAmount - _discount)
                            .clamp(0.0, double.infinity);
                      }
                      setState(() => _currentStep = 1);
                    },
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSupplierSelectorCard(BuildContext context) {
    final theme = Theme.of(context);
    final hasSupplier = _selectedSupplier != null;

    return Card(
      elevation: 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.grey200),
      ),
      color: AppColors.white,
      child: InkWell(
        key: const Key('select_supplier_btn'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showSupplierSelectSheet(context),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: "Nhà cung cấp" on the left, "Bỏ chọn" (or chevron) on the right (same row!)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.business,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        'Nhà cung cấp',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  if (hasSupplier)
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        setState(() => _selectedSupplier = null);
                      },
                      child: const Padding(
                        padding:
                            EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                        child: Text(
                          'Bỏ chọn',
                          style: TextStyle(
                            color: AppColors.danger,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else
                    const Icon(Icons.chevron_right,
                        color: AppColors.grey400, size: 18),
                ],
              ),
              const SizedBox(height: 6),
              // Row 2: Selected supplier info OR prompt
              if (!hasSupplier)
                const Text(
                  'Chưa chọn Nhà Cung Cấp (Bấm để chọn)',
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.grey400,
                    fontWeight: FontWeight.w500,
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _selectedSupplier!.name,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textTitle,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_selectedSupplier!.code.isNotEmpty) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _selectedSupplier!.code,
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _selectedSupplier!.currentDebt > 0
                            ? AppColors.dangerLight
                            : AppColors.successLight,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        _selectedSupplier!.currentDebt > 0
                            ? 'Nợ: ${NumberFormat('#,###', 'vi_VN').format(_selectedSupplier!.currentDebt)} đ'
                            : 'Không có nợ',
                        style: TextStyle(
                          fontSize: 11,
                          color: _selectedSupplier!.currentDebt > 0
                              ? AppColors.dangerDark
                              : AppColors.successDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProductSearchBar(
    BuildContext context,
    List<Product> products,
    String currentStoreId,
  ) {
    final filtered = _selectedCategory == null
        ? products
        : products.where((p) => p.category == _selectedCategory).toList();

    return Row(
      children: [
        Expanded(
          child: Autocomplete<Product>(
            displayStringForOption: (product) =>
                '${product.name} • ${product.code}',
            optionsBuilder: (textEditingValue) {
              if (textEditingValue.text.isEmpty) {
                return const Iterable<Product>.empty();
              }
              final query = textEditingValue.text.toLowerCase().trim();
              return filtered.where((p) {
                return p.name.toLowerCase().contains(query) ||
                    p.code.toLowerCase().contains(query) ||
                    (p.barcode != null && p.barcode!.contains(query));
              });
            },
            onSelected: (product) {
              _openProductEditSheet(product, currentStoreId);
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return ListenableBuilder(
                listenable: controller,
                builder: (context, _) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      labelText: 'Tìm kiếm sản phẩm',
                      hintText: 'Tên, mã SKU, mã vạch...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: controller.text.isNotEmpty
                          ? IconButton(
                              key: const Key('btn_clear_product_search'),
                              icon: const Icon(Icons.clear,
                                  size: 18, color: AppColors.grey400),
                              tooltip: 'Xóa tìm kiếm',
                              onPressed: () {
                                controller.clear();
                              },
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  );
                },
              );
            },
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          key: const Key('btn_barcode_scanner'),
          icon:
              const Icon(Icons.qr_code_scanner, color: AppColors.primaryAction),
          tooltip: 'Quét mã vạch',
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Tính năng quét mã vạch đang được kích hoạt'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildCategoryChips(List<Product> products) {
    final categories = products
        .map((p) => p.category)
        .where((c) => c.trim().isNotEmpty)
        .toSet()
        .toList();

    if (categories.isEmpty) return const SizedBox.shrink();

    return Container(
      height: 38,
      margin: const EdgeInsets.only(top: 2, bottom: 4),
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: categories.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (ctx, index) {
          if (index == 0) {
            final isSelected = _selectedCategory == null;
            return ChoiceChip(
              label: const Text('Tất cả', style: TextStyle(fontSize: 12)),
              selected: isSelected,
              onSelected: (_) => setState(() => _selectedCategory = null),
            );
          }
          final cat = categories[index - 1];
          final isSelected = _selectedCategory == cat;
          return ChoiceChip(
            label: Text(cat, style: const TextStyle(fontSize: 12)),
            selected: isSelected,
            onSelected: (sel) {
              setState(() => _selectedCategory = sel ? cat : null);
            },
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: AppColors.primaryLight,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 30,
                color: AppColors.primaryAction,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Chưa có hàng trong phiếu',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.textTitle,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Tìm kiếm hoặc quét mã vạch để thêm sản phẩm vào phiếu nhập',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.grey600),
            ),
          ],
        ),
      ),
    );
  }

  void _showSupplierSelectSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return _SupplierSelectSheet(
          selectedSupplierId: _selectedSupplier?.id,
          onSupplierSelected: (supplier) {
            setState(() => _selectedSupplier = supplier);
          },
        );
      },
    );
  }
}

class _SupplierSelectSheet extends ConsumerStatefulWidget {
  final String? selectedSupplierId;
  final ValueChanged<Supplier> onSupplierSelected;

  const _SupplierSelectSheet({
    required this.selectedSupplierId,
    required this.onSupplierSelected,
  });

  @override
  ConsumerState<_SupplierSelectSheet> createState() =>
      _SupplierSelectSheetState();
}

class _SupplierSelectSheetState extends ConsumerState<_SupplierSelectSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final suppliersAsync = ref.watch(supplierListNotifierProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.8,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Chọn Nhà Cung Cấp',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('quick_add_supplier_btn'),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Thêm mới NCC'),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    onPressed: () async {
                      final navigator = Navigator.of(context);
                      final newSupplier = await navigator.push<Supplier>(
                        MaterialPageRoute(
                          builder: (_) => const AddEditSupplierPage(),
                        ),
                      );
                      if (!mounted) return;
                      if (newSupplier != null) {
                        widget.onSupplierSelected(newSupplier);
                        navigator.pop();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Search input
              TextField(
                key: const Key('supplier_search_field'),
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Tìm theo tên, mã NCC, SĐT...',
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
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onChanged: (val) =>
                    setState(() => _searchQuery = val.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              // Suppliers list
              Expanded(
                child: suppliersAsync.when(
                  data: (suppliers) {
                    final filtered = suppliers.where((s) {
                      if (_searchQuery.isEmpty) return true;
                      return s.name.toLowerCase().contains(_searchQuery) ||
                          s.code.toLowerCase().contains(_searchQuery) ||
                          s.phone.toLowerCase().contains(_searchQuery);
                    }).toList();

                    if (filtered.isEmpty) {
                      return const Center(
                          child: Text('Không tìm thấy Nhà Cung Cấp'));
                    }

                    return ListView.separated(
                      controller: scrollController,
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final supplier = filtered[index];
                        final isSelected =
                            supplier.id == widget.selectedSupplierId;

                        return ListTile(
                          selected: isSelected,
                          selectedTileColor: theme.colorScheme.primaryContainer
                              .withOpacity(0.3),
                          leading: CircleAvatar(
                            backgroundColor:
                                theme.colorScheme.primary.withOpacity(0.1),
                            child: Text(
                              supplier.name.isNotEmpty
                                  ? supplier.name[0].toUpperCase()
                                  : 'N',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          title: Text(
                            supplier.name,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            '${supplier.code} • ${supplier.phone}',
                            style: const TextStyle(
                                color: AppColors.grey600, fontSize: 12),
                          ),
                          trailing: isSelected
                              ? Icon(Icons.check_circle,
                                  color: theme.colorScheme.primary)
                              : null,
                          onTap: () {
                            widget.onSupplierSelected(supplier);
                            Navigator.of(context).pop();
                          },
                        );
                      },
                    );
                  },
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('Lỗi: $e')),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
