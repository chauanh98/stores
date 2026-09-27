import 'dart:io';

import '../../../application/products/services/image_upload_service.dart';
import '../../../core/utils/image_compression_helper.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/inventory/inventory_providers.dart';
import '../../../application/products/categories_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/inventory_transaction.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/product_unit.dart';
import '../../../domain/entities/transaction_type.dart';
import '../../common/widgets/loading_indicator.dart';
import '../../common/widgets/product_image_thumbnail.dart';
import '../../inventories/pages/import_inventory_page.dart';
import '../../inventories/pages/inter_store_transfer_page.dart';
import '../../inventories/widgets/stock_in_receipt_detail_bottom_sheet.dart';
import '../widgets/sample_image_picker_dialog.dart';
import 'select_brand_page.dart';
import 'select_category_page.dart';

class ProductDetailPage extends ConsumerStatefulWidget {
  final Product? product;
  final String? productId;

  const ProductDetailPage({
    super.key,
    this.product,
    this.productId,
  }) : assert(product != null || productId != null,
            'Either product or productId must be provided');

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  bool _isEditing = false;
  bool _isLoading = false;
  bool _controllersInitialized = false;
  late Product _currentProduct;
  int _txFilterIndex =
      0; // 0: Tất cả, 1: Nhập hàng, 2: Bán hàng / Xuất, 3: Chuyển kho

  // Collapsible section states for Details Page
  bool _showDetailsDesc = false;
  bool _showDetailsStockLimits = false;

  // Controllers for Edit Form
  late TextEditingController _nameController;
  late TextEditingController _codeController;
  late TextEditingController _barcodeController;
  late TextEditingController _brandController;
  late TextEditingController _priceController;
  late TextEditingController _costPriceController;
  late TextEditingController _stockController;
  late TextEditingController _descriptionController;
  late TextEditingController _minStockController;
  late TextEditingController _maxStockController;
  late TextEditingController _noteTemplateController;
  late TextEditingController _componentsController;

  Category? _selectedCategory;
  String _selectedCategoryPath = '';

  // Edit Image Upload State
  File? _newImageFile;
  Uint8List? _newImageBytes;
  bool _clearCurrentImage = false;
  String? _newOnlineImageUrl;

  // Attributes & Units states for Edit Form
  List<Map<String, String>> _attributes = [];
  List<Map<String, dynamic>> _units = [];
  bool _sellDirectly = true;

  bool _isMinimalPlaceholder(Product? p) {
    if (p == null) return true;
    return p.code.isEmpty &&
        p.price == 0 &&
        p.costPrice == 0 &&
        p.category.isEmpty;
  }

  @override
  void initState() {
    super.initState();
    final initialProduct = widget.product;
    final isPlaceholder = _isMinimalPlaceholder(initialProduct);

    if (initialProduct != null) {
      _currentProduct = initialProduct;
      _initializeControllers();
    } else {
      _currentProduct = Product(
        id: widget.productId ?? '',
        name: '',
        code: '',
        price: 0,
        costPrice: 0,
        branchStocks: const {},
        category: '',
      );
      _initializeControllers();
    }

    if (isPlaceholder || initialProduct == null) {
      _isLoading = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _loadProductFallback();
      });
    }
  }

  Future<void> _loadProductFallback() async {
    final targetId = widget.productId ?? widget.product?.id;
    if (targetId == null || targetId.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final fetched =
          await ref.read(productRepositoryProvider).fetchById(targetId);
      if (fetched != null && mounted) {
        setState(() {
          _currentProduct = fetched;
          _initializeControllers();
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _disposeControllers() {
    if (!_controllersInitialized) return;
    _nameController.dispose();
    _codeController.dispose();
    _barcodeController.dispose();
    _brandController.dispose();
    _priceController.dispose();
    _costPriceController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    _minStockController.dispose();
    _maxStockController.dispose();
    _noteTemplateController.dispose();
    _componentsController.dispose();
    _controllersInitialized = false;
  }

  void _initializeControllers() {
    final currentStoreId = ref.read(currentStoreIdProvider);
    final branchStock = _currentProduct.stockInBranch(currentStoreId);
    _sellDirectly = _currentProduct.allowSale;
    _nameController = TextEditingController(text: _currentProduct.name);
    _codeController = TextEditingController(text: _currentProduct.code);
    _barcodeController =
        TextEditingController(text: _currentProduct.barcode ?? '');
    _brandController = TextEditingController(text: _currentProduct.brand ?? '');
    _priceController =
        TextEditingController(text: _currentProduct.price.toStringAsFixed(0));
    _costPriceController = TextEditingController(
        text: _currentProduct.costPrice.toStringAsFixed(0));
    _stockController = TextEditingController(text: branchStock.toString());
    _descriptionController =
        TextEditingController(text: _currentProduct.description ?? '');

    _minStockController =
        TextEditingController(text: _currentProduct.minStock?.toString() ?? '');
    _maxStockController =
        TextEditingController(text: _currentProduct.maxStock?.toString() ?? '');

    _noteTemplateController =
        TextEditingController(text: _currentProduct.noteTemplate ?? '');
    _componentsController =
        TextEditingController(text: _currentProduct.components ?? '');

    _selectedCategoryPath =
        _currentProduct.category3Levels ?? _currentProduct.category;

    // Parse model field as attributes (stored as "key:value, key:value")
    _attributes = [];
    if (_currentProduct.model != null && _currentProduct.model!.isNotEmpty) {
      try {
        final pairs = _currentProduct.model!.split(', ');
        for (final pair in pairs) {
          final parts = pair.split(':');
          if (parts.length == 2) {
            _attributes.add({'name': parts[0], 'value': parts[1]});
          }
        }
      } catch (_) {}
    }

    _units = [];
    if (_currentProduct.units.isNotEmpty) {
      _units = _currentProduct.units
          .map((u) => {
                'id': u.id,
                'name': u.unitName,
                'unitName': u.unitName,
                'conversionRate': u.conversionRate,
                'price': u.price,
                'costPrice': u.costPrice,
                'barcode': u.barcode,
                'code': u.code,
                'isDirectSale': u.isDirectSale,
              })
          .toList();
    } else if (_currentProduct.unit != null &&
        _currentProduct.unit!.isNotEmpty) {
      _units.add({
        'id': 'base_unit',
        'name': _currentProduct.unit,
        'unitName': _currentProduct.unit,
        'conversionRate': 1,
        'price': _currentProduct.price,
        'costPrice': _currentProduct.costPrice,
        'isDirectSale': true,
      });
    }

    _clearCurrentImage = false;
    _newImageFile = null;
    _newImageBytes = null;
    _newOnlineImageUrl = null;
    _controllersInitialized = true;
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final user = ref.watch(authProvider);
    final canManageProducts = user?.canManageProducts ?? false;
    final canViewCostPrice = user?.canViewCostPrice ?? false;
    final showCostPrice = ref.watch(showCostPriceProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Thông tin cơ bản' : l10n.productDetail,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: AppColors.white,
        actions: [
          if (!_isEditing) ...[
            if (!_isLoading) ...[
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                onPressed: () {
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (context) =>
                        InterStoreTransferPage(product: _currentProduct),
                  ));
                },
                tooltip: l10n.transferProduct,
              ),
              if (canManageProducts) ...[
                TextButton(
                  onPressed: () {
                    _initializeControllers();
                    setState(() => _isEditing = true);
                  },
                  child: const Text('Sửa',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.delete_outline, color: AppColors.danger),
                  onPressed: _showDeleteDialog,
                  tooltip: l10n.delete,
                ),
              ],
            ],
          ] else ...[
            TextButton(
              onPressed: _isLoading ? null : _saveProduct,
              child: const Text('Lưu',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _isLoading ? null : _cancelEdit,
              tooltip: l10n.cancel,
            ),
          ],
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isEditing) ...[
                    // 1. Details Page View
                    _buildProductHeader(context),
                    const SizedBox(height: 12),

                    // Quick Action Shortcuts Bar
                    _buildQuickActionsBar(context, canManageProducts),
                    const SizedBox(height: 12),

                    // Product Information Card
                    _buildBasicInfoCard(context, currencyFormat,
                        canViewCostPrice, showCostPrice),
                    const SizedBox(height: 12),

                    // Converted Units Table
                    if (_currentProduct.units.isNotEmpty) ...[
                      _buildConvertedUnitsCard(context, currencyFormat,
                          canViewCostPrice, showCostPrice),
                      const SizedBox(height: 12),
                    ],

                    // Combo Components Card
                    if (_currentProduct.isCombo) ...[
                      _buildComboComponentsCard(context, currencyFormat,
                          canViewCostPrice, showCostPrice),
                      const SizedBox(height: 12),
                    ],

                    // Inline Branch Stock Table Card
                    _buildBranchStockCard(context),
                    const SizedBox(height: 12),

                    // Collapsible description
                    _buildDetailsActionRow(
                      icon: Icons.notes,
                      label: 'Mô tả',
                      onTap: () =>
                          setState(() => _showDetailsDesc = !_showDetailsDesc),
                      isToggled: _showDetailsDesc,
                    ),
                    if (_showDetailsDesc) ...[
                      const SizedBox(height: 8),
                      _buildDetailsCollapsibleCard(
                          _currentProduct.description ?? 'Không có mô tả'),
                    ],
                    const SizedBox(height: 8),

                    // Collapsible stock limits
                    _buildDetailsActionRow(
                      icon: Icons.notifications_active_outlined,
                      label: 'Định mức tồn kho',
                      onTap: () => setState(() =>
                          _showDetailsStockLimits = !_showDetailsStockLimits),
                      isToggled: _showDetailsStockLimits,
                    ),
                    if (_showDetailsStockLimits) ...[
                      const SizedBox(height: 8),
                      _buildDetailsCollapsibleCard(
                          'Tồn tối thiểu: ${_currentProduct.minStock ?? 0} • Tồn tối đa: ${_currentProduct.maxStock ?? 999999999}'),
                    ],
                    const SizedBox(height: 8),

                    // Stock Card History Tab / Section ("Lịch sử thẻ kho")
                    _buildStockCardSection(context, currencyFormat,
                        canViewCostPrice, showCostPrice),
                    const SizedBox(height: 12),

                    // Direct Selling switch (Cho phép bán / Ngừng kinh doanh)
                    Card(
                      color: AppColors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.borderLight),
                      ),
                      child: SwitchListTile(
                        value: _currentProduct.allowSale,
                        onChanged: canManageProducts
                            ? (v) => _toggleAllowSale(v, canManageProducts)
                            : null,
                        title: const Text(
                          'Cho phép bán',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: AppColors.textPrimary),
                        ),
                        subtitle: Text(
                          _currentProduct.allowSale
                              ? 'Đang kinh doanh (Hiển thị trên POS và cho phép bán hàng)'
                              : 'Ngừng kinh doanh (Tự động ẩn khỏi màn hình POS)',
                          style: TextStyle(
                            fontSize: 11,
                            color: _currentProduct.allowSale
                                ? AppColors.successDark
                                : AppColors.dangerDark,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        activeColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 48),
                  ] else ...[
                    // 2. Edit Form View
                    _buildEditForm(),
                  ],
                ],
              ),
            ),
    );
  }

  // Header sản phẩm (Tên, Ảnh & Trạng thái tồn kho)
  Widget _buildProductHeader(BuildContext context) {
    final isOutOfStock = _currentProduct.isOutOfStock;
    final isLowStock = _currentProduct.isLowStock();

    Color statusBgColor;
    Color statusTextColor;
    String statusText;

    if (isOutOfStock) {
      statusBgColor = AppColors.dangerLight;
      statusTextColor = AppColors.dangerDark;
      statusText = 'Hết hàng';
    } else if (isLowStock) {
      statusBgColor = AppColors.warningLight;
      statusTextColor = AppColors.warningDark;
      statusText = 'Sắp hết (${_currentProduct.stock})';
    } else {
      statusBgColor = AppColors.successLight;
      statusTextColor = AppColors.successDark;
      statusText = 'Còn hàng (${_currentProduct.stock})';
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              final urls = _currentProduct.allImageUrls;
              if (urls.isNotEmpty) {
                _showImageGalleryDialog(context, urls, _currentProduct.name);
              }
            },
            child: Stack(
              children: [
                ProductImageThumbnail(
                  imageUrl: _currentProduct.primaryImageUrl ??
                      _currentProduct.imageUrl,
                  productName: _currentProduct.name,
                  categoryName: _currentProduct.category,
                  size: 64,
                  borderRadius: 10,
                ),
                if (_currentProduct.allImageUrls.length > 1)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppColors.black.withOpacity(0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '+${_currentProduct.allImageUrls.length}',
                        style: const TextStyle(
                          color: AppColors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        _currentProduct.name,
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                      ),
                    ),
                    if (_currentProduct.isCombo) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: AppColors.primary.withOpacity(0.3)),
                        ),
                        child: const Text(
                          'COMBO',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBgColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: statusTextColor,
                        ),
                      ),
                    ),
                    if (!_currentProduct.allowSale)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.dangerLight,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.dangerBorder),
                        ),
                        child: const Text(
                          'Ngừng kinh doanh',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppColors.dangerDark,
                          ),
                        ),
                      ),
                    if (_currentProduct.brand != null &&
                        _currentProduct.brand!.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.grey300),
                        ),
                        child: Text(
                          _currentProduct.brand!,
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Quick Action Shortcuts Bar
  Widget _buildQuickActionsBar(BuildContext context, bool canManageProducts) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Expanded(
            child: _buildQuickActionButton(
              icon: Icons.input_rounded,
              label: 'Nhập hàng',
              color: AppColors.successDark,
              bgColor: AppColors.successLight,
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => const ImportInventoryPage(),
                ));
              },
            ),
          ),
          Expanded(
            child: _buildQuickActionButton(
              icon: Icons.swap_horiz_rounded,
              label: 'Chuyển kho',
              color: AppColors.primaryDark,
              bgColor: AppColors.primaryLight,
              onTap: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) =>
                      InterStoreTransferPage(product: _currentProduct),
                ));
              },
            ),
          ),
          Expanded(
            child: _buildQuickActionButton(
              icon: Icons.edit_outlined,
              label: 'Chỉnh sửa',
              color: AppColors.primary,
              bgColor: AppColors.primary.withOpacity(0.08),
              onTap: () {
                if (canManageProducts) {
                  _initializeControllers();
                  setState(() => _isEditing = true);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Bạn không có quyền chỉnh sửa sản phẩm')),
                  );
                }
              },
            ),
          ),
          Expanded(
            child: _buildQuickActionButton(
              icon: Icons.qr_code_2_rounded,
              label: 'In mã vạch',
              color: AppColors.supervisorDark,
              bgColor: AppColors.supervisorLight,
              onTap: () => _showBarcodePrintDialog(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required Color color,
    required Color bgColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: bgColor,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppColors.grey800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Basic Info Card
  Widget _buildBasicInfoCard(
    BuildContext context,
    NumberFormat format,
    bool canViewCostPrice,
    bool showCostPrice,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _buildDetailRow('Mã hàng', _currentProduct.code, true),
          const Divider(height: 1, color: AppColors.divider),
          _buildDetailRow('Mã vạch', _currentProduct.barcode ?? '—', true),
          const Divider(height: 1, color: AppColors.divider),
          _buildDetailRow('Tên hàng', _currentProduct.name, false),
          const Divider(height: 1, color: AppColors.divider),
          _buildDetailRow('Thương hiệu', _currentProduct.brand ?? '—', false),
          const Divider(height: 1, color: AppColors.divider),
          _buildDetailRow('Nhóm hàng', _selectedCategoryPath, false),
          const Divider(height: 1, color: AppColors.divider),
          _buildDetailRow('Đơn vị cơ bản', _currentProduct.unit ?? '—', false),
          const Divider(height: 1, color: AppColors.divider),
          _buildDetailRow(
              'Giá bán', '${format.format(_currentProduct.price)} đ', false),
          if (canViewCostPrice) ...[
            const Divider(height: 1, color: AppColors.divider),
            _buildCostPriceRow(format, showCostPrice),
          ],
        ],
      ),
    );
  }

  Widget _buildCostPriceRow(NumberFormat format, bool showCostPrice) {
    final costPriceText = showCostPrice
        ? '${format.format(_currentProduct.costPrice)} đ'
        : '••••••';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Text(
                'Giá vốn',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(width: 4),
              IconButton(
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                icon: Icon(
                  showCostPrice
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                onPressed: () {
                  ref.read(showCostPriceProvider.notifier).state =
                      !showCostPrice;
                },
                tooltip: 'Ẩn / Hiện giá vốn',
              ),
            ],
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              costPriceText,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Converted Units Card
  Widget _buildConvertedUnitsCard(
    BuildContext context,
    NumberFormat format,
    bool canViewCostPrice,
    bool showCostPrice,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.straighten_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Đơn vị tính quy đổi',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentProduct.units.length} đơn vị',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _currentProduct.units.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.dividerLight),
            itemBuilder: (context, index) {
              final unit = _currentProduct.units[index];
              final baseUnitName = _currentProduct.unit ?? 'đơn vị cơ bản';
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'x${unit.conversionRate}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                unit.unitName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (unit.isDirectSale) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: AppColors.success.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    'Bán POS',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: AppColors.success,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '1 ${unit.unitName} = ${unit.conversionRate} $baseUnitName',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          if (unit.barcode != null && unit.barcode!.isNotEmpty)
                            Text(
                              'Mã vạch: ${unit.barcode}',
                              style: const TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${format.format(unit.price)} đ',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (canViewCostPrice && unit.costPrice != null)
                          Text(
                            showCostPrice
                                ? 'Vốn: ${format.format(unit.costPrice)} đ'
                                : 'Vốn: ••••••',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // Combo Components Card
  Widget _buildComboComponentsCard(
    BuildContext context,
    NumberFormat format,
    bool canViewCostPrice,
    bool showCostPrice,
  ) {
    if (!_currentProduct.isCombo || _currentProduct.comboComponents.isEmpty) {
      return const SizedBox.shrink();
    }

    final allProducts = ref.watch(productListProvider).value ?? [];
    final Map<String, Product> productMap = {
      for (final p in allProducts) p.id: p
    };

    double totalComponentsCost = 0.0;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.widgets_outlined,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Thành phần trong Combo',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_currentProduct.comboComponents.length} món',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _currentProduct.comboComponents.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: AppColors.dividerLight),
            itemBuilder: (context, index) {
              final comp = _currentProduct.comboComponents[index];
              final child = productMap[comp.productId];
              final childCost = child?.costPrice ?? comp.costPrice ?? 0.0;
              totalComponentsCost += childCost * comp.quantity;

              final stockDT = child?.stockInBranch('store_001') ?? 0;
              final stockTB = child?.stockInBranch('store_002') ?? 0;

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'x${comp.quantity}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comp.productName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            canViewCostPrice
                                ? (showCostPrice
                                    ? 'Mã: ${comp.productCode} • Giá vốn lẻ: ${format.format(childCost)} đ'
                                    : 'Mã: ${comp.productCode} • Giá vốn lẻ: ••••••')
                                : 'Mã: ${comp.productCode}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tồn kho linh kiện: ĐT: $stockDT | TB: $stockTB',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canViewCostPrice) ...[
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          showCostPrice
                              ? '${format.format(childCost * comp.quantity)} đ'
                              : '••••••',
                          textAlign: TextAlign.end,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
          if (canViewCostPrice) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Flexible(
                    child: Text(
                      'Tổng giá vốn gợi ý linh kiện:',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      showCostPrice
                          ? '${format.format(totalComponentsCost)} đ'
                          : '••••••',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, bool isCopyable) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    value,
                    textAlign: TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: AppColors.textPrimary),
                  ),
                ),
                if (isCopyable && value != '—') ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: value));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Đã sao chép: $value')),
                      );
                    },
                    child: const Icon(Icons.copy_outlined,
                        size: 14, color: AppColors.primary),
                  )
                ]
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Inline Branch Stock Table Card
  Widget _buildBranchStockCard(BuildContext context) {
    final branches = ref.watch(branchesProvider);

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.storefront_rounded,
                        color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Phân bổ tồn kho theo chi nhánh',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'Tổng: ${_currentProduct.stock}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.divider),
          const SizedBox(height: 8),
          ...branches.map((branch) {
            final branchStock = _currentProduct.stockInBranch(branch.id);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: branchStock > 0
                                ? AppColors.success
                                : AppColors.grey400,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            branch.name,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: branchStock > 0
                          ? AppColors.successLight
                          : AppColors.grey100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '$branchStock',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: branchStock > 0
                            ? AppColors.successDark
                            : AppColors.grey600,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
          const Divider(height: 1, color: AppColors.dividerLight),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  'Tổng tồn toàn chuỗi',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: AppColors.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_currentProduct.stock}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailsActionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isToggled,
  }) {
    return Card(
      color: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 20),
        title: Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        trailing: Icon(
            isToggled ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
            size: 20),
        onTap: onTap,
        dense: true,
      ),
    );
  }

  Widget _buildDetailsCollapsibleCard(String text) {
    return Card(
      color: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary)),
      ),
    );
  }

  // Stock Card History Tab / Section ("Lịch sử thẻ kho")
  Widget _buildStockCardSection(
    BuildContext context,
    NumberFormat format,
    bool canViewCostPrice,
    bool showCostPrice,
  ) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer(
      builder: (context, ref, child) {
        final txAsync =
            ref.watch(transactionsByProductProvider(_currentProduct.id));
        return Container(
          decoration: BoxDecoration(
            color: AppColors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.history_rounded,
                      color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Lịch sử thẻ kho',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: AppColors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 5 Filter Segments
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                      value: 0,
                      label: Text('Tất cả', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 1,
                      label: Text('Nhập hàng', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 2,
                      label: Text('Bán hàng / Xuất',
                          style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 3,
                      label: Text('Chuyển kho', style: TextStyle(fontSize: 11)),
                    ),
                    ButtonSegment(
                      value: 4,
                      label:
                          Text('Cân bằng kho', style: TextStyle(fontSize: 11)),
                    ),
                  ],
                  selected: {_txFilterIndex},
                  onSelectionChanged: (set) {
                    setState(() => _txFilterIndex = set.first);
                  },
                  style: SegmentedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              txAsync.when(
                data: (txs) {
                  final filtered = txs.where((t) {
                    final isAudit = t.type == TransactionType.inventoryAudit ||
                        _isAuditTx(t);
                    final isTransfer = _isTransferTx(t) && !isAudit;
                    if (_txFilterIndex == 1) {
                      return t.type == TransactionType.import &&
                          !isTransfer &&
                          !isAudit;
                    }
                    if (_txFilterIndex == 2) {
                      return t.type == TransactionType.export &&
                          !isTransfer &&
                          !isAudit;
                    }
                    if (_txFilterIndex == 3) {
                      return isTransfer;
                    }
                    if (_txFilterIndex == 4) {
                      return isAudit;
                    }
                    return true;
                  }).toList()
                    ..sort((a, b) => b.date.compareTo(a.date));

                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text(
                          'Chưa có lịch sử giao dịch',
                          style: TextStyle(
                            color: AppColors.textMuted,
                            fontSize: 13,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: AppColors.dividerLight),
                    itemBuilder: (context, index) {
                      final tx = filtered[index];
                      final isAudit =
                          tx.type == TransactionType.inventoryAudit ||
                              _isAuditTx(tx);
                      final isTransfer = _isTransferTx(tx) && !isAudit;
                      final isImport = tx.type == TransactionType.import;

                      Color badgeBg;
                      Color badgeIconColor;
                      IconData badgeIcon;
                      String typeBadgeText;

                      if (isAudit) {
                        badgeBg = AppColors.supervisorLight;
                        badgeIconColor = AppColors.supervisorDark;
                        badgeIcon = Icons.tune_rounded;
                        typeBadgeText = 'Cân bằng kho';
                      } else if (isTransfer) {
                        badgeBg = AppColors.primaryLight;
                        badgeIconColor = AppColors.primaryDark;
                        badgeIcon = Icons.swap_horiz_rounded;
                        typeBadgeText = 'Chuyển kho';
                      } else if (isImport) {
                        badgeBg = AppColors.successLight;
                        badgeIconColor = AppColors.successDark;
                        badgeIcon = Icons.call_received_rounded;
                        typeBadgeText = 'Nhập hàng';
                      } else {
                        badgeBg = AppColors.dangerLight;
                        badgeIconColor = AppColors.dangerDark;
                        badgeIcon = Icons.call_made_rounded;
                        typeBadgeText = 'Bán hàng / Xuất';
                      }

                      final isPositiveAudit = isAudit &&
                          (tx.isAuditNegative != null
                              ? tx.isAuditNegative == false
                              : (tx.note.contains('chênh lệch: +') ||
                                  (tx.note.contains('+') &&
                                      !tx.note.contains('-'))));
                      final isNegativeAudit = isAudit &&
                          (tx.isAuditNegative != null
                              ? tx.isAuditNegative == true
                              : (tx.note.contains('chênh lệch: -') ||
                                  (!tx.note.contains('+') &&
                                      tx.note.contains('-'))));

                      final isPositive = isImport || isPositiveAudit;
                      final isNegative =
                          tx.type == TransactionType.export || isNegativeAudit;
                      final sign = isPositive ? '+' : (isNegative ? '-' : '');
                      final signColor = isPositive
                          ? AppColors.successDark
                          : AppColors.dangerDark;

                      String noteText;
                      if (isAudit) {
                        noteText = tx.note.isNotEmpty
                            ? tx.note
                            : 'Cân bằng kho trực tiếp';
                      } else if (isTransfer) {
                        noteText = tx.note;
                      } else if (isImport) {
                        noteText = tx.note.isNotEmpty ? tx.note : 'Nhập kho';
                      } else {
                        noteText = tx.note.isNotEmpty
                            ? (tx.note.contains('Chuyển') ||
                                    tx.note.contains('Nhận')
                                ? tx.note
                                : 'Bán hàng (Mã đơn: ${tx.note})')
                            : 'Xuất kho';
                      }

                      final canTapReceipt = isImport ||
                          (tx.importCode != null && tx.importCode!.isNotEmpty);

                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: canTapReceipt
                            ? () => StockInReceiptDetailBottomSheet.show(
                                  context,
                                  importCode: tx.importCode,
                                  transaction: tx,
                                )
                            : null,
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: badgeBg,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            badgeIcon,
                            color: badgeIconColor,
                            size: 18,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(
                              DateFormat('dd/MM/yyyy HH:mm').format(tx.date),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: badgeBg,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                typeBadgeText,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: badgeIconColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 2),
                            Text(
                              noteText,
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11),
                            ),
                            if (tx.importCode != null &&
                                tx.importCode!.isNotEmpty)
                              Text(
                                'Mã phiếu: ${tx.importCode}',
                                style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            Text(
                              '${l10n.performedBy}: ${tx.createdByName ?? tx.createdBy ?? '—'}',
                              style: const TextStyle(
                                  color: AppColors.textSecondary, fontSize: 11),
                            ),
                            if (tx.importPrice != null && canViewCostPrice)
                              Text(
                                showCostPrice
                                    ? '${isAudit ? 'Giá vốn' : 'Giá nhập'}: ${format.format(tx.importPrice)} đ'
                                    : '${isAudit ? 'Giá vốn' : 'Giá nhập'}: ••••••',
                                style: const TextStyle(
                                    color: AppColors.textTertiary,
                                    fontSize: 11),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '$sign${tx.quantity}',
                              style: TextStyle(
                                color: signColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            if (canTapReceipt) ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.chevron_right,
                                  size: 16, color: AppColors.textMuted),
                            ],
                          ],
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: LoadingIndicator()),
                error: (e, _) => Center(
                    child: Text('Lỗi tải thẻ kho: $e',
                        style: const TextStyle(fontSize: 12))),
              )
            ],
          ),
        );
      },
    );
  }

  bool _isAuditTx(InventoryTransaction tx) {
    if (tx.type == TransactionType.inventoryAudit) return true;
    final noteLower = tx.note.toLowerCase();
    return noteLower.contains('cân bằng') ||
        noteLower.contains('audit') ||
        noteLower.contains('điều chỉnh');
  }

  bool _isTransferTx(InventoryTransaction tx) {
    final noteLower = tx.note.toLowerCase();
    return noteLower.contains('chuyển') ||
        noteLower.contains('nhận') ||
        noteLower.contains('transfer') ||
        noteLower.contains('điều chuyển');
  }

  // Barcode Display & Print Dialog
  void _showBarcodePrintDialog(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final barcodeValue =
        (_currentProduct.barcode != null && _currentProduct.barcode!.isNotEmpty)
            ? _currentProduct.barcode!
            : _currentProduct.code;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.qr_code_2_rounded, color: AppColors.primary),
              SizedBox(width: 8),
              Text(
                'Mã vạch sản phẩm',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                _currentProduct.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Mã SKU: ${_currentProduct.code}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              // Stylized Barcode Simulation Box
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.grey300),
                ),
                child: Column(
                  children: [
                    // Simulated barcode stripes
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(24, (i) {
                        final isThick = (i % 3 == 0) || (i % 7 == 0);
                        return Container(
                          width: isThick ? 4 : 2,
                          height: 48,
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          color: AppColors.textPrimary,
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      barcodeValue,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        letterSpacing: 2.0,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Giá bán: ${currencyFormat.format(_currentProduct.price)} đ',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Đóng'),
            ),
            OutlinedButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Sao chép mã'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: barcodeValue));
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Đã sao chép mã vạch: $barcodeValue')),
                );
              },
            ),
            FilledButton.icon(
              icon: const Icon(Icons.print_rounded, size: 16),
              label: const Text('In mã vạch'),
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              onPressed: () {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                        'Đang gửi lệnh in mã vạch cho sản phẩm ${_currentProduct.name}...'),
                    backgroundColor: AppColors.success,
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }

  // Toggle "Cho phép bán / Ngừng kinh doanh" directly from details
  void _toggleAllowSale(bool v, bool canManageProducts) async {
    if (!canManageProducts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn không có quyền thay đổi trạng thái kinh doanh!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() {
      _sellDirectly = v;
      _isLoading = true;
    });

    try {
      final updated = _currentProduct.copyWith(
        allowSale: v,
      );
      await ref.read(productRepositoryProvider).upsert(updated);
      ref.invalidate(productListProvider);
      if (!mounted) return;
      setState(() {
        _currentProduct = updated;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(v
              ? 'Đã kích hoạt kinh doanh sản phẩm!'
              : 'Đã chuyển sản phẩm sang Ngừng kinh doanh!'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi: $e')),
      );
    }
  }

  // ----------------------------------------------------
  // EDIT FORM VIEW SECTION
  // ----------------------------------------------------

  Widget _buildEditForm() {
    return Column(
      children: [
        // Image Editor Card
        _buildImageEditorCard(),
        const SizedBox(height: 16),

        // Fields Card
        Card(
          color: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.borderLight),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildEditField(_codeController, 'Mã hàng', Icons.tag),
                const SizedBox(height: 16),
                _buildEditField(_barcodeController, 'Mã vạch', Icons.qr_code),
                const SizedBox(height: 16),
                _buildEditField(_nameController, 'Tên hàng *', Icons.label,
                    required: true),
                const SizedBox(height: 16),
                _buildCategorySelector(),
                const SizedBox(height: 16),
                _buildBrandSelector(),
                const SizedBox(height: 16),
                _buildEditField(_costPriceController, 'Giá vốn', Icons.download,
                    isNumber: true, hint: '0'),
                const SizedBox(height: 16),
                _buildEditField(_priceController, 'Giá bán', Icons.upload,
                    isNumber: true, hint: '0'),
                if (!_currentProduct.isCombo) ...[
                  const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final currentStoreId = ref.watch(currentStoreIdProvider);
                      final branches = ref.watch(branchesProvider);
                      final activeBranch = branches.firstWhere(
                        (b) => b.id == currentStoreId,
                        orElse: () => Branch(
                          currentStoreId,
                          currentStoreId == 'store_002'
                              ? 'Chi nhánh Thới Bình'
                              : 'Chi nhánh Đông Thắng',
                        ),
                      );
                      final stockLabel =
                          'Số lượng tồn kho (${activeBranch.name})';
                      return _buildEditField(
                        _stockController,
                        stockLabel,
                        Icons.inventory_2,
                        isNumber: true,
                        hint: '0',
                      );
                    },
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(8),
                      border:
                          Border.all(color: AppColors.primary.withOpacity(0.2)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            color: AppColors.primary, size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Tồn kho của Combo được tự động tính theo số lượng linh kiện thành phần.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textPrimary),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Description
        _buildEditActionRow(
          icon: Icons.notes,
          label: 'Nhập mô tả',
          onTap: () => setState(() => _showDetailsDesc = !_showDetailsDesc),
          isToggled: _showDetailsDesc,
        ),
        if (_showDetailsDesc) ...[
          const SizedBox(height: 8),
          _buildEditCollapsibleInput(
              _descriptionController, 'Nhập mô tả sản phẩm...',
              maxLines: 3),
        ],
        const SizedBox(height: 8),

        // Attributes
        _buildEditActionRow(
          icon: Icons.style,
          label: 'Sửa thuộc tính',
          onTap: _showAttributesDialog,
          trailingWidget: _attributes.isNotEmpty
              ? Chip(label: Text('${_attributes.length} thuộc tính'))
              : null,
        ),
        if (_attributes.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildAttributesList(),
        ],
        const SizedBox(height: 8),

        // Units
        _buildEditActionRow(
          icon: Icons.straighten,
          label: 'Sửa đơn vị tính',
          onTap: _showUnitsDialog,
          trailingWidget: _units.isNotEmpty
              ? Chip(label: Text('${_units.length} ĐVT'))
              : null,
        ),
        if (_units.isNotEmpty) ...[
          const SizedBox(height: 8),
          _buildUnitsList(),
        ],
        const SizedBox(height: 8),

        // Stock Limits
        _buildEditActionRow(
          icon: Icons.notifications_active_outlined,
          label: 'Sửa định mức tồn kho',
          onTap: () => setState(
              () => _showDetailsStockLimits = !_showDetailsStockLimits),
          isToggled: _showDetailsStockLimits,
        ),
        if (_showDetailsStockLimits) ...[
          const SizedBox(height: 8),
          _buildStockLimitsInputs(),
        ],
        const SizedBox(height: 8),

        // Switch allowSale in edit form
        Card(
          color: AppColors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.borderLight),
          ),
          child: SwitchListTile(
            value: _sellDirectly,
            onChanged: (v) => setState(() => _sellDirectly = v),
            title: const Text(
              'Cho phép bán',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppColors.textPrimary),
            ),
            subtitle: Text(
              _sellDirectly
                  ? 'Đang kinh doanh (Hiển thị trên POS và cho phép bán hàng)'
                  : 'Ngừng kinh doanh (Tự động ẩn khỏi màn hình POS)',
              style: TextStyle(
                fontSize: 11,
                color: _sellDirectly
                    ? AppColors.successDark
                    : AppColors.dangerDark,
                fontWeight: FontWeight.w500,
              ),
            ),
            activeColor: AppColors.primary,
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  Widget _buildImageEditorCard() {
    final resolvedNewOnline =
        ImageCompressionHelper.resolvePrimaryUrl(_newOnlineImageUrl);
    final hasNewOnline =
        resolvedNewOnline != null && resolvedNewOnline.isNotEmpty;
    final primaryCurrentUrl = _currentProduct.primaryImageUrl ??
        ProductImageThumbnail.resolvePrimaryUrl(_currentProduct.imageUrl);
    final showCurrentImage = primaryCurrentUrl != null &&
        primaryCurrentUrl.isNotEmpty &&
        !_clearCurrentImage &&
        _newImageFile == null &&
        _newImageBytes == null &&
        !hasNewOnline;

    final hasAnyImage = showCurrentImage ||
        _newImageFile != null ||
        _newImageBytes != null ||
        hasNewOnline;

    final bool isShowingBase64 = (hasNewOnline &&
            ImageCompressionHelper.isBase64DataUrl(resolvedNewOnline)) ||
        (showCurrentImage &&
            ImageCompressionHelper.isBase64DataUrl(primaryCurrentUrl));

    return GestureDetector(
      onTap: _showImageSourceSheet,
      child: Card(
        color: AppColors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppColors.borderLight),
        ),
        child: Container(
          height: 150,
          width: double.infinity,
          alignment: Alignment.center,
          child: hasAnyImage
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: hasNewOnline
                            ? (ImageCompressionHelper.isBase64DataUrl(
                                    resolvedNewOnline)
                                ? Builder(
                                    builder: (context) {
                                      final bytes = ImageCompressionHelper
                                          .decodeBase64DataUrl(
                                              resolvedNewOnline);
                                      if (bytes != null && bytes.isNotEmpty) {
                                        return Image.memory(
                                          bytes,
                                          fit: BoxFit.cover,
                                          cacheWidth: 300,
                                          cacheHeight: 300,
                                          errorBuilder: (_, __, ___) =>
                                              Container(
                                            color: AppColors.grey100,
                                            child: const Center(
                                              child: Icon(Icons.broken_image,
                                                  color: AppColors.danger,
                                                  size: 36),
                                            ),
                                          ),
                                        );
                                      }
                                      return Container(
                                        color: AppColors.grey100,
                                        child: const Center(
                                          child: Icon(Icons.broken_image,
                                              color: AppColors.danger,
                                              size: 36),
                                        ),
                                      );
                                    },
                                  )
                                : (resolvedNewOnline.startsWith('http://') ||
                                        resolvedNewOnline
                                            .startsWith('https://'))
                                    ? Image.network(
                                        resolvedNewOnline,
                                        fit: BoxFit.cover,
                                        cacheWidth: 300,
                                        cacheHeight: 300,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: AppColors.grey100,
                                          child: const Center(
                                            child: Column(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Icon(Icons.broken_image,
                                                    color: AppColors.danger,
                                                    size: 36),
                                                SizedBox(height: 4),
                                                Text('Link ảnh không hợp lệ',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color:
                                                            AppColors.danger)),
                                              ],
                                            ),
                                          ),
                                        ),
                                      )
                                    : Container(
                                        color: AppColors.grey100,
                                        child: const Center(
                                          child: Icon(Icons.broken_image,
                                              color: AppColors.danger,
                                              size: 36),
                                        ),
                                      ))
                            : _newImageFile != null
                                ? Image.file(
                                    _newImageFile!,
                                    fit: BoxFit.cover,
                                    cacheWidth: 300,
                                    cacheHeight: 300,
                                    errorBuilder: (_, __, ___) => Container(
                                      color: AppColors.grey100,
                                      child: const Center(
                                        child: Icon(Icons.broken_image,
                                            color: AppColors.danger, size: 36),
                                      ),
                                    ),
                                  )
                                : _newImageBytes != null
                                    ? Image.memory(
                                        _newImageBytes!,
                                        fit: BoxFit.cover,
                                        cacheWidth: 300,
                                        cacheHeight: 300,
                                        errorBuilder: (_, __, ___) => Container(
                                          color: AppColors.grey100,
                                          child: const Center(
                                            child: Icon(Icons.broken_image,
                                                color: AppColors.danger,
                                                size: 36),
                                          ),
                                        ),
                                      )
                                    : (ImageCompressionHelper.isBase64DataUrl(
                                            primaryCurrentUrl)
                                        ? Builder(
                                            builder: (context) {
                                              final bytes =
                                                  ImageCompressionHelper
                                                      .decodeBase64DataUrl(
                                                          primaryCurrentUrl);
                                              if (bytes != null &&
                                                  bytes.isNotEmpty) {
                                                return Image.memory(
                                                  bytes,
                                                  fit: BoxFit.cover,
                                                  cacheWidth: 300,
                                                  cacheHeight: 300,
                                                  errorBuilder: (_, __, ___) =>
                                                      Container(
                                                    color: AppColors.grey100,
                                                    child: const Center(
                                                      child: Icon(
                                                          Icons.broken_image,
                                                          color:
                                                              AppColors.danger,
                                                          size: 36),
                                                    ),
                                                  ),
                                                );
                                              }
                                              return Container(
                                                color: AppColors.grey100,
                                                child: const Center(
                                                  child: Icon(
                                                      Icons.broken_image,
                                                      color: AppColors.danger,
                                                      size: 36),
                                                ),
                                              );
                                            },
                                          )
                                        : (primaryCurrentUrl != null &&
                                                (primaryCurrentUrl.startsWith(
                                                        'http://') ||
                                                    primaryCurrentUrl
                                                        .startsWith(
                                                            'https://')))
                                            ? Image.network(
                                                primaryCurrentUrl,
                                                fit: BoxFit.cover,
                                                cacheWidth: 300,
                                                cacheHeight: 300,
                                                errorBuilder: (_, __, ___) =>
                                                    Container(
                                                  color: AppColors.grey100,
                                                  child: const Center(
                                                    child: Column(
                                                      mainAxisAlignment:
                                                          MainAxisAlignment
                                                              .center,
                                                      children: [
                                                        Icon(Icons.broken_image,
                                                            color: AppColors
                                                                .danger,
                                                            size: 36),
                                                        SizedBox(height: 4),
                                                        Text(
                                                            'Không thể tải ảnh',
                                                            style: TextStyle(
                                                                fontSize: 12,
                                                                color: AppColors
                                                                    .danger)),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              )
                                            : Container(
                                                color: AppColors.grey100,
                                                child: const Center(
                                                  child: Icon(
                                                      Icons.broken_image,
                                                      color: AppColors.danger,
                                                      size: 36),
                                                ),
                                              )),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _newImageFile = null;
                          _newImageBytes = null;
                          _newOnlineImageUrl = null;
                          if (_currentProduct.imageUrl != null) {
                            _clearCurrentImage = true;
                          }
                        }),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: AppColors.black.withOpacity(0.6),
                          child: const Icon(Icons.close,
                              color: AppColors.white, size: 16),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: GestureDetector(
                          onTap: () {
                            if (isShowingBase64) {
                              ImageUploadService.showStorageActivationGuide(
                                  context);
                            } else {
                              _showImageSourceSheet();
                            }
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isShowingBase64
                                    ? Icons.shield_outlined
                                    : Icons.edit,
                                color: isShowingBase64
                                    ? AppColors.warning
                                    : AppColors.white,
                                size: 12,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isShowingBase64
                                    ? 'Ảnh dự phòng (Base64)'
                                    : (_newImageFile != null ||
                                            _newImageBytes != null
                                        ? 'Ảnh mới'
                                        : (hasNewOnline
                                            ? 'Link Online'
                                            : 'Đổi ảnh')),
                                style: const TextStyle(
                                    color: AppColors.white, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              : const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate_outlined,
                        size: 36, color: AppColors.grey400),
                    SizedBox(height: 6),
                    Text('Thêm ảnh sản phẩm',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600)),
                    SizedBox(height: 2),
                    Text(
                      'Tự chọn ảnh hoặc lấy gợi ý ảnh mẫu thông minh',
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    )
                  ],
                ),
        ),
      ),
    );
  }

  void _showImageGalleryDialog(
      BuildContext context, List<String> imageUrls, String title) {
    if (imageUrls.isEmpty) return;
    showDialog(
      context: context,
      barrierColor: AppColors.textPrimary,
      builder: (dialogCtx) => _ProductImageGalleryDialog(
        imageUrls: imageUrls,
        title: title,
      ),
    );
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.successLight,
                    child: Icon(Icons.auto_awesome,
                        color: AppColors.success, size: 20),
                  ),
                  title: const Text('Gợi ý ảnh mẫu thông minh',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Tự động gợi ý ảnh đẹp theo tên và ngành hàng'),
                  onTap: () async {
                    Navigator.pop(context);
                    final selectedUrl = await SampleImagePickerDialog.show(
                      context,
                      productName: _nameController.text.trim().isNotEmpty
                          ? _nameController.text.trim()
                          : _currentProduct.name,
                      category: _selectedCategoryPath.isNotEmpty
                          ? _selectedCategoryPath
                          : _currentProduct.category,
                      brand: _brandController.text.trim().isNotEmpty
                          ? _brandController.text.trim()
                          : _currentProduct.brand,
                      category3Levels: _selectedCategoryPath,
                      isCombo: _currentProduct.isCombo,
                    );
                    if (selectedUrl != null && mounted) {
                      setState(() {
                        _newOnlineImageUrl = selectedUrl;
                        _newImageFile = null;
                        _newImageBytes = null;
                        _clearCurrentImage = false;
                      });
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.orangeLight,
                    child: Icon(Icons.camera_alt,
                        color: AppColors.warning, size: 20),
                  ),
                  title: const Text('Chụp ảnh từ Camera',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Chụp ảnh trực tiếp sản phẩm tại quầy'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImageFromCamera();
                  },
                ),
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    child: const Icon(Icons.photo_library,
                        color: AppColors.primary, size: 20),
                  ),
                  title: const Text('Chọn ảnh từ Thư viện',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Tải ảnh có sẵn từ máy hoặc máy tính'),
                  onTap: () {
                    Navigator.pop(context);
                    _pickImageFromFile();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.tealLight,
                    child:
                        Icon(Icons.link, color: AppColors.chartTeal, size: 20),
                  ),
                  title: const Text('Nhập / Dán Link ảnh Online',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle:
                      const Text('Dán link ảnh từ Google Images hoặc website'),
                  onTap: () {
                    Navigator.pop(context);
                    _showImageUrlDialog();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _processPickedImage(XFile? pickedFile) async {
    if (pickedFile == null) return;
    try {
      final rawBytes = await pickedFile.readAsBytes();
      final compressedBytes = ImageCompressionHelper.compressImageBytes(
        rawBytes,
        maxWidth: 350,
        maxHeight: 350,
        quality: 70,
      );
      final dataUrl = ImageCompressionHelper.toBase64DataUrl(compressedBytes);
      if (mounted) {
        setState(() {
          _newOnlineImageUrl = dataUrl;
          _newImageBytes = compressedBytes;
          _newImageFile = null;
          _clearCurrentImage = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xử lý ảnh: $e')),
        );
      }
    }
  }

  void _pickImageFromCamera() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
      );
      await _processPickedImage(pickedFile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chụp ảnh: $e')),
        );
      }
    }
  }

  void _pickImageFromFile() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 75,
      );
      await _processPickedImage(pickedFile);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chọn ảnh: $e')),
        );
      }
    }
  }

  void _showImageUrlDialog() {
    final urlController = TextEditingController(text: _newOnlineImageUrl ?? '');
    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Nhập Link Ảnh Online',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dán link ảnh từ website nhà sản xuất, Google Images hoặc link online:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                decoration: const InputDecoration(
                  labelText: 'URL hình ảnh (https://...)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                  hintText: 'https://example.com/product.jpg',
                ),
                keyboardType: TextInputType.url,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final url = urlController.text.trim();
                if (url.isNotEmpty) {
                  setState(() {
                    _newOnlineImageUrl = url;
                    _newImageFile = null;
                    _newImageBytes = null;
                    _clearCurrentImage = true;
                  });
                }
                Navigator.pop(dialogContext);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Xác nhận'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditField(
      TextEditingController controller, String label, IconData icon,
      {bool required = false, bool isNumber = false, String? hint}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textTertiary),
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) {
          return 'Vui lòng nhập $label';
        }
        return null;
      },
    );
  }

  Widget _buildCategorySelector() {
    return InkWell(
      onTap: _navigateToCategorySelect,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Nhóm hàng *',
          prefixIcon: Icon(Icons.category, color: AppColors.textTertiary),
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _selectedCategoryPath.isNotEmpty
                    ? _selectedCategoryPath
                    : 'Chọn nhóm hàng',
                style: TextStyle(
                  color: _selectedCategoryPath.isNotEmpty
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _navigateToCategorySelect() async {
    final selected = await Navigator.push<Category>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SelectCategoryPage(initialCategory: _selectedCategory),
      ),
    );

    if (selected != null) {
      final categories = ref.read(categoryListProvider).value ?? [];
      final path = <String>[selected.name];
      final visited = <String>{selected.id};
      var current = selected;
      while (current.parentId != null && current.parentId!.trim().isNotEmpty) {
        final pid = current.parentId!.trim();
        final parent = categories.cast<Category?>().firstWhere(
              (c) => c?.id == pid,
              orElse: () => null,
            );
        if (parent == null || parent.id.isEmpty) break;
        if (!visited.add(parent.id)) break; // Cycle guard
        path.insert(0, parent.name);
        current = parent;
      }

      setState(() {
        _selectedCategory = selected;
        _selectedCategoryPath = path.join(' >> ');
      });
    }
  }

  Widget _buildBrandSelector() {
    return InkWell(
      onTap: _navigateToBrandSelect,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Thương hiệu',
          prefixIcon: Icon(Icons.business, color: AppColors.textTertiary),
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _brandController.text.isNotEmpty
                    ? _brandController.text
                    : 'Chọn thương hiệu',
                style: TextStyle(
                  color: _brandController.text.isNotEmpty
                      ? AppColors.textPrimary
                      : AppColors.textMuted,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }

  void _navigateToBrandSelect() async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SelectBrandPage(initialBrand: _brandController.text),
      ),
    );

    if (selected != null) {
      setState(() {
        _brandController.text = selected;
      });
    }
  }

  Widget _buildEditActionRow({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool? isToggled,
    Widget? trailingWidget,
  }) {
    return Card(
      color: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: AppColors.primary, size: 20),
        title: Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary)),
        trailing: trailingWidget ??
            (isToggled != null
                ? Icon(isToggled
                    ? Icons.keyboard_arrow_up
                    : Icons.keyboard_arrow_down)
                : const Icon(Icons.chevron_right)),
        onTap: onTap,
        dense: true,
      ),
    );
  }

  Widget _buildEditCollapsibleInput(
      TextEditingController controller, String hint,
      {int maxLines = 1}) {
    return Card(
      color: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TextFormField(
          controller: controller,
          maxLines: maxLines,
          decoration: InputDecoration(
            hintText: hint,
            border: const OutlineInputBorder(),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ),
    );
  }

  Widget _buildStockLimitsInputs() {
    return Card(
      color: AppColors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _minStockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Tồn ít nhất', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: _maxStockController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Tồn nhiều nhất', border: OutlineInputBorder()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttributesList() {
    return Column(
      children: _attributes.map((attr) {
        return Card(
          color: AppColors.white,
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            title: Text('${attr['name']}: ${attr['value']}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.danger, size: 18),
              onPressed: () {
                setState(() {
                  _attributes.remove(attr);
                });
              },
            ),
            dense: true,
          ),
        );
      }).toList(),
    );
  }

  void _showAttributesDialog() {
    final nameController = TextEditingController();
    final valueController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Thêm thuộc tính'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Tên thuộc tính (Ví dụ: Màu sắc, Kích thước...)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: valueController,
                decoration: const InputDecoration(
                    labelText: 'Giá trị (Ví dụ: Đỏ, Xanh, L, XL...)',
                    border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final val = valueController.text.trim();
                if (name.isNotEmpty && val.isNotEmpty) {
                  setState(() {
                    _attributes.add({'name': name, 'value': val});
                  });
                }
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Thêm'),
            )
          ],
        );
      },
    );
  }

  Widget _buildUnitsList() {
    return Column(
      children: _units.map((unit) {
        final uName = unit['unitName'] ?? unit['name'] ?? '';
        final uPrice = unit['price'] ?? 0;
        return Card(
          color: AppColors.white,
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            title: Text('$uName',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('Giá bán: $uPrice đ'),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline,
                  color: AppColors.danger, size: 18),
              onPressed: () {
                setState(() {
                  _units.remove(unit);
                });
              },
            ),
            dense: true,
          ),
        );
      }).toList(),
    );
  }

  void _showUnitsDialog() {
    final nameController = TextEditingController();
    final priceController = TextEditingController();
    final rateController = TextEditingController(text: '1');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Thêm đơn vị tính'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                    labelText: 'Tên đơn vị (Ví dụ: Cái, Hộp, Thùng...)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: rateController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Tỷ lệ quy đổi (so với cơ bản)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Giá bán quy đổi', border: OutlineInputBorder()),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                final price =
                    double.tryParse(priceController.text.trim()) ?? 0.0;
                final rate = int.tryParse(rateController.text.trim()) ?? 1;
                if (name.isNotEmpty) {
                  setState(() {
                    _units.add({
                      'id': 'unit_${DateTime.now().millisecondsSinceEpoch}',
                      'name': name,
                      'unitName': name,
                      'conversionRate': rate,
                      'price': price,
                      'isDirectSale': true,
                    });
                  });
                }
                Navigator.pop(context);
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Thêm'),
            )
          ],
        );
      },
    );
  }

  Future<void> _saveProduct() async {
    final l10n = AppLocalizations.of(context)!;
    if (_nameController.text.trim().isEmpty ||
        _codeController.text.trim().isEmpty ||
        _priceController.text.trim().isEmpty ||
        _costPriceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseFillAllField)),
      );
      return;
    }

    final price = double.tryParse(_priceController.text.trim());
    final costPrice = double.tryParse(_costPriceController.text.trim());
    final stock = int.tryParse(_stockController.text.trim()) ?? 0;

    if (price == null || costPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterValidNumber)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final storeId = ref.read(currentStoreIdProvider);
      String? imageUrl = _currentProduct.imageUrl;

      bool isFallbackImage = false;
      // Handle image deletion and upload
      final bool hasNewImageInput = _newImageFile != null ||
          _newImageBytes != null ||
          (_newOnlineImageUrl != null && _newOnlineImageUrl!.isNotEmpty);

      if (hasNewImageInput) {
        try {
          if (_newOnlineImageUrl != null && _newOnlineImageUrl!.isNotEmpty) {
            final oldUrl = _currentProduct.imageUrl;
            imageUrl = _newOnlineImageUrl;
            if (oldUrl != null && oldUrl.isNotEmpty && oldUrl != imageUrl) {
              await ref
                  .read(imageUploadServiceProvider)
                  .deleteProductImage(oldUrl);
            }
          } else if (_newImageFile != null || _newImageBytes != null) {
            final uploadResult =
                await ref.read(imageUploadServiceProvider).uploadProductImage(
                      storeId: storeId,
                      productId: _currentProduct.id,
                      file: _newImageFile,
                      bytes: _newImageBytes,
                    );
            if (uploadResult.imageUrl.isNotEmpty) {
              final oldUrl = _currentProduct.imageUrl;
              imageUrl = uploadResult.imageUrl;
              isFallbackImage = uploadResult.isFallbackBase64;
              if (oldUrl != null && oldUrl.isNotEmpty && oldUrl != imageUrl) {
                await ref
                    .read(imageUploadServiceProvider)
                    .deleteProductImage(oldUrl);
              }
            }
          }
        } catch (e, stack) {
          debugPrint(
              '[_saveChanges] Safe image upload suppressed error: $e\n$stack');
        }
      } else if (_clearCurrentImage) {
        if (_currentProduct.imageUrl != null &&
            _currentProduct.imageUrl!.isNotEmpty) {
          try {
            await ref
                .read(imageUploadServiceProvider)
                .deleteProductImage(_currentProduct.imageUrl!);
          } catch (e) {
            debugPrint('[_saveChanges] Safe delete product image error: $e');
          }
        }
        imageUrl = null;
      }

      // Convert attributes list to model field string
      final modelString =
          _attributes.map((a) => '${a['name']}:${a['value']}').join(', ');
      final categoryName = _selectedCategory?.name ?? _currentProduct.category;

      final minStock = int.tryParse(_minStockController.text.trim());
      final maxStock = int.tryParse(_maxStockController.text.trim());

      final updatedUnits = _units.map((u) {
        return ProductUnit(
          id: u['id']?.toString() ??
              'unit_${DateTime.now().millisecondsSinceEpoch}',
          unitName: (u['unitName'] ?? u['name'] ?? '').toString(),
          conversionRate: (u['conversionRate'] as num?)?.toInt() ?? 1,
          price: (u['price'] as num?)?.toDouble() ?? 0.0,
          costPrice: (u['costPrice'] as num?)?.toDouble(),
          barcode: u['barcode']?.toString(),
          code: u['code']?.toString(),
          isDirectSale: (u['isDirectSale'] as bool?) ?? true,
        );
      }).toList();

      final currentStoreId = ref.read(currentStoreIdProvider);
      final updatedBranchStocks =
          Map<String, int>.from(_currentProduct.branchStocks);

      final oldBranchStock = _currentProduct.stockInBranch(currentStoreId);
      final stockDiff = stock - oldBranchStock;

      // Assign to branch stock key matching active branch
      String targetKey = currentStoreId;
      if (!updatedBranchStocks.containsKey(currentStoreId)) {
        if (currentStoreId == 'store_001' &&
            updatedBranchStocks.containsKey('branch_1')) {
          targetKey = 'branch_1';
        } else if (currentStoreId == 'store_002' &&
            updatedBranchStocks.containsKey('branch_2')) {
          targetKey = 'branch_2';
        }
      }
      updatedBranchStocks[targetKey] = stock;

      if (stockDiff != 0 && !_currentProduct.isCombo) {
        final now = DateTime.now();
        final user = ref.read(authProvider);
        final auditTx = InventoryTransaction(
          id: 'audit_${now.millisecondsSinceEpoch}_${_currentProduct.id}',
          productId: _currentProduct.id,
          type: TransactionType.inventoryAudit,
          quantity: stockDiff.abs(),
          date: now,
          note:
              'Cân bằng kho trực tiếp (Tồn cũ: $oldBranchStock -> Tồn mới: $stock, chênh lệch: ${stockDiff > 0 ? "+$stockDiff" : "$stockDiff"})',
          importPrice: costPrice,
          createdBy: user?.username,
          createdByName: user?.name,
          storeId: currentStoreId,
          isAuditNegative: stockDiff < 0,
          auditDifference: stockDiff,
        );
        await ref.read(inventoryRepositoryProvider).record(auditTx);
      }

      final updatedProduct = Product(
        id: _currentProduct.id,
        name: _nameController.text.trim(),
        code: _codeController.text.trim(),
        barcode: _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        brand: _brandController.text.trim().isNotEmpty
            ? _brandController.text.trim()
            : null,
        model: modelString.isNotEmpty ? modelString : null,
        price: price,
        costPrice: costPrice,
        branchStocks: updatedBranchStocks,
        category: categoryName,
        category3Levels:
            _selectedCategoryPath.isNotEmpty ? _selectedCategoryPath : null,
        unit: updatedUnits.isNotEmpty
            ? updatedUnits.first.unitName
            : _currentProduct.unit,
        description: _descriptionController.text.trim().isNotEmpty
            ? _descriptionController.text.trim()
            : null,
        noteTemplate: _noteTemplateController.text.trim().isNotEmpty
            ? _noteTemplateController.text.trim()
            : null,
        components: _componentsController.text.trim().isNotEmpty
            ? _componentsController.text.trim()
            : null,
        imageUrl: imageUrl,
        type: _currentProduct.type ?? 'Hàng hóa',
        isCombo: _currentProduct.isCombo,
        comboComponents: _currentProduct.comboComponents,
        minStock: minStock,
        maxStock: maxStock,
        units: updatedUnits.isNotEmpty ? updatedUnits : _currentProduct.units,
        allowSale: _sellDirectly,
      );

      await ref.read(productRepositoryProvider).upsert(updatedProduct);
      ref.invalidate(productListProvider);
      ref.invalidate(transactionsByProductProvider(_currentProduct.id));

      if (mounted) {
        setState(() {
          _currentProduct = updatedProduct;
          _newImageFile = null;
          _newImageBytes = null;
          _newOnlineImageUrl = null;
          _clearCurrentImage = false;
          _isEditing = false;
        });
        final String successMessage = isFallbackImage
            ? 'Đã cập nhật sản phẩm (Ảnh được lưu dự phòng do Cloud Storage chưa kích hoạt)'
            : l10n.updated;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(successMessage),
            backgroundColor: AppColors.success,
            duration: Duration(seconds: isFallbackImage ? 5 : 3),
            action: isFallbackImage
                ? SnackBarAction(
                    label: 'Hướng dẫn',
                    textColor: AppColors.white,
                    onPressed: () {
                      if (context.mounted) {
                        ImageUploadService.showStorageActivationGuide(context);
                      }
                    },
                  )
                : null,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi cập nhật: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _cancelEdit() {
    _initializeControllers();
    setState(() => _isEditing = false);
  }

  void _showDeleteDialog() {
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text('${l10n.wantToDelete} "${_currentProduct.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _deleteProduct();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteProduct() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _isLoading = true);

    try {
      if (_currentProduct.imageUrl != null &&
          _currentProduct.imageUrl!.isNotEmpty) {
        await ref
            .read(imageUploadServiceProvider)
            .deleteProductImage(_currentProduct.imageUrl!);
      }

      await ref.read(productRepositoryProvider).delete(_currentProduct.id);
      ref.invalidate(productListProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.updated), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi xóa sản phẩm: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}

class _ProductImageGalleryDialog extends StatefulWidget {
  final List<String> imageUrls;
  final String title;

  const _ProductImageGalleryDialog({
    required this.imageUrls,
    required this.title,
  });

  @override
  State<_ProductImageGalleryDialog> createState() =>
      _ProductImageGalleryDialogState();
}

class _ProductImageGalleryDialogState
    extends State<_ProductImageGalleryDialog> {
  late final PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.transparent,
      insetPadding: const EdgeInsets.all(12),
      child: Stack(
        children: [
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.65,
                  width: double.infinity,
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: widget.imageUrls.length,
                    onPageChanged: (index) {
                      setState(() => _currentIndex = index);
                    },
                    itemBuilder: (context, index) {
                      final url = widget.imageUrls[index];
                      Widget imageWidget;
                      if (ImageCompressionHelper.isBase64DataUrl(url)) {
                        final bytes =
                            ImageCompressionHelper.decodeBase64DataUrl(url);
                        if (bytes != null && bytes.isNotEmpty) {
                          imageWidget = Image.memory(
                            bytes,
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) => const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.broken_image,
                                      color: AppColors.white70, size: 48),
                                  SizedBox(height: 8),
                                  Text('Không thể tải ảnh này',
                                      style:
                                          TextStyle(color: AppColors.white70)),
                                ],
                              ),
                            ),
                          );
                        } else {
                          imageWidget = const Center(
                            child: Icon(Icons.broken_image,
                                color: AppColors.white70, size: 48),
                          );
                        }
                      } else if (url.startsWith('http://') ||
                          url.startsWith('https://')) {
                        imageWidget = Image.network(
                          url,
                          fit: BoxFit.contain,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return const Center(
                              child: CircularProgressIndicator(
                                  color: AppColors.white),
                            );
                          },
                          errorBuilder: (_, __, ___) => const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.broken_image,
                                    color: AppColors.white70, size: 48),
                                SizedBox(height: 8),
                                Text('Không thể tải ảnh này',
                                    style: TextStyle(color: AppColors.white70)),
                              ],
                            ),
                          ),
                        );
                      } else {
                        imageWidget = const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.broken_image,
                                  color: AppColors.white70, size: 48),
                              SizedBox(height: 8),
                              Text('Không thể tải ảnh này',
                                  style: TextStyle(color: AppColors.white70)),
                            ],
                          ),
                        );
                      }
                      return InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 3.5,
                        child: imageWidget,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (widget.imageUrls.length > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      widget.imageUrls.length,
                      (index) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: _currentIndex == index ? 20 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _currentIndex == index
                              ? AppColors.white
                              : AppColors.white70,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
                Text(
                  '${_currentIndex + 1} / ${widget.imageUrls.length} • ${widget.title}',
                  style: const TextStyle(
                    color: AppColors.white70,
                    fontSize: 13,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              icon: const Icon(Icons.close, color: AppColors.white, size: 28),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ],
      ),
    );
  }
}
