import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
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
import '../../../domain/entities/product.dart';
import '../../common/widgets/loading_indicator.dart';
import '../../common/widgets/product_image_thumbnail.dart';
import '../../inventories/pages/inter_store_transfer_page.dart';
import 'select_brand_page.dart';
import 'select_category_page.dart';

class ProductDetailPage extends ConsumerStatefulWidget {
  final Product product;

  const ProductDetailPage({
    super.key,
    required this.product,
  });

  @override
  ConsumerState<ProductDetailPage> createState() => _ProductDetailPageState();
}

class _ProductDetailPageState extends ConsumerState<ProductDetailPage> {
  bool _isEditing = false;
  bool _isLoading = false;
  late Product _currentProduct;
  int _txFilterIndex = 0; // 0: All, 1: Imports, 2: Exports

  // Collapsible section states for Details Page
  bool _showDetailsDesc = false;
  bool _showDetailsStockLimits = false;
  bool _showDetailsOther = false;

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

  // Attributes & Units states for Edit Form
  List<Map<String, String>> _attributes = [];
  List<Map<String, dynamic>> _units = [];
  bool _sellDirectly = true;

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.product;
    _initializeControllers();
  }

  void _initializeControllers() {
    _nameController = TextEditingController(text: _currentProduct.name);
    _codeController = TextEditingController(text: _currentProduct.code);
    _barcodeController =
        TextEditingController(text: _currentProduct.barcode ?? '');
    _brandController = TextEditingController(text: _currentProduct.brand ?? '');
    _priceController =
        TextEditingController(text: _currentProduct.price.toStringAsFixed(0));
    _costPriceController = TextEditingController(
        text: _currentProduct.costPrice.toStringAsFixed(0));
    _stockController =
        TextEditingController(text: _currentProduct.stock.toString());
    _descriptionController =
        TextEditingController(text: _currentProduct.description ?? '');

    // Parse stock limits if available
    _minStockController = TextEditingController();
    _maxStockController = TextEditingController();

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
    if (_currentProduct.unit != null && _currentProduct.unit!.isNotEmpty) {
      _units
          .add({'name': _currentProduct.unit, 'price': _currentProduct.price});
    }

    _clearCurrentImage = false;
    _newImageFile = null;
    _newImageBytes = null;
  }

  @override
  void dispose() {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final user = ref.watch(authProvider);
    final canManageProducts = user?.canManageProducts ?? false;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEditing ? 'Thông tin cơ bản' : l10n.productDetail,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        actions: [
          if (!_isEditing) ...[
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
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                onPressed: _showDeleteDialog,
                tooltip: l10n.delete,
              ),
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
                    _buildBasicInfoCard(context, currencyFormat),
                    if (_currentProduct.isCombo) ...[
                      const SizedBox(height: 12),
                      _buildComboComponentsCard(context, currencyFormat),
                    ],
                    const SizedBox(height: 12),
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
                          'Tồn tối thiểu: 0 • Tồn tối đa: 999,999,999'),
                    ],
                    const SizedBox(height: 8),

                    // Transaction list (Thẻ kho)
                    _buildStockCardSection(context, currencyFormat),
                    const SizedBox(height: 12),

                    // Direct Selling switch
                    Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.borderLight),
                      ),
                      child: SwitchListTile(
                        value: _sellDirectly,
                        onChanged: (v) => _toggleSellDirectly(v),
                        title: const Text(
                          'Bán trực tiếp',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87),
                        ),
                        subtitle: const Text(
                            'Cho phép sản phẩm bán trực tiếp tại quầy POS',
                            style: TextStyle(fontSize: 11)),
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

  // Header sản phẩm (Tên, Ảnh & Thương hiệu)
  Widget _buildProductHeader(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          ProductImageThumbnail(
            imageUrl: _currentProduct.imageUrl,
            productName: _currentProduct.name,
            categoryName: _currentProduct.category,
            size: 56,
            borderRadius: 8,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Basic Info Card
  Widget _buildBasicInfoCard(BuildContext context, NumberFormat format) {
    final user = ref.watch(authProvider);
    final canViewCostPrice = user?.canViewCostPrice ?? false;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _buildDetailRow('Mã hàng', _currentProduct.code, true),
          const Divider(height: 1, color: AppColors.divider),
          _buildDetailRow('Mã vạch', _currentProduct.barcode ?? '—', true),
          if (canViewCostPrice) ...[
            const Divider(height: 1, color: AppColors.divider),
            _buildDetailRow('Giá vốn',
                '${format.format(_currentProduct.costPrice)} đ', false),
          ],
          const Divider(height: 1, color: AppColors.divider),
          _buildDetailRow(
              'Giá bán', '${format.format(_currentProduct.price)} đ', false),
          const Divider(height: 1, color: AppColors.divider),
          _buildDetailRow('Nhóm hàng', _selectedCategoryPath, false),
        ],
      ),
    );
  }

  // Combo Components Card
  Widget _buildComboComponentsCard(BuildContext context, NumberFormat format) {
    if (!_currentProduct.isCombo || _currentProduct.comboComponents.isEmpty) {
      return const SizedBox.shrink();
    }

    final user = ref.watch(authProvider);
    final canViewCostPrice = user?.canViewCostPrice ?? false;

    final allProducts = ref.watch(productListProvider).value ?? [];
    final Map<String, Product> productMap = {
      for (final p in allProducts) p.id: p
    };

    double totalComponentsCost = 0.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
              const Text(
                'Thành phần trong Combo',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: Colors.black87,
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

              final stockB1 = child?.branchStocks['branch_1'] ?? 0;
              final stockB2 = child?.branchStocks['branch_2'] ?? 0;

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
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            canViewCostPrice
                                ? 'Mã: ${comp.productCode} • Giá vốn lẻ: ${format.format(childCost)} đ'
                                : 'Mã: ${comp.productCode}',
                            style: const TextStyle(
                              color: Colors.black54,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Tồn kho linh kiện: CN1: $stockB1 | CN2: $stockB2',
                            style: const TextStyle(
                              color: Colors.black45,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (canViewCostPrice)
                      Text(
                        '${format.format(childCost * comp.quantity)} đ',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          color: Colors.black87,
                        ),
                      ),
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
                  const Text(
                    'Tổng giá vốn gợi ý linh kiện:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  Text(
                    '${format.format(totalComponentsCost)} đ',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
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
        children: [
          Text(label,
              style: const TextStyle(color: Colors.black54, fontSize: 13)),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Colors.black87),
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
          )
        ],
      ),
    );
  }

  // Branch Stock Card
  Widget _buildBranchStockCard(BuildContext context) {
    return InkWell(
      onTap: () => _showBranchStockBottomSheet(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tồn kho',
                  style: TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tổng tồn: ${_currentProduct.stock}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: Colors.black87),
                )
              ],
            ),
            Row(
              children: const [
                Text(
                  'Chi tiết',
                  style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 4),
                Icon(Icons.chevron_right, color: AppColors.primary, size: 18),
              ],
            )
          ],
        ),
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
      color: Colors.white,
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
                color: Colors.black87)),
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
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(text,
            style: const TextStyle(fontSize: 13, color: Colors.black87)),
      ),
    );
  }

  Widget _buildStockCardSection(BuildContext context, NumberFormat format) {
    final l10n = AppLocalizations.of(context)!;
    return Consumer(
      builder: (context, ref, child) {
        final txAsync =
            ref.watch(transactionsByProductProvider(_currentProduct.id));
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
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
                  const Text(
                    'Thẻ kho',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87),
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(
                          value: 0,
                          label:
                              Text('Tất cả', style: TextStyle(fontSize: 10))),
                      ButtonSegment(
                          value: 1,
                          label: Text('Nhập', style: TextStyle(fontSize: 10))),
                      ButtonSegment(
                          value: 2,
                          label: Text('Xuất', style: TextStyle(fontSize: 10))),
                    ],
                    selected: {_txFilterIndex},
                    onSelectionChanged: (set) {
                      setState(() => _txFilterIndex = set.first);
                    },
                    style: SegmentedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              txAsync.when(
                data: (txs) {
                  final filtered = txs.where((t) {
                    if (_txFilterIndex == 1) return t.type.name == 'import';
                    if (_txFilterIndex == 2) return t.type.name == 'export';
                    return true;
                  }).toList()
                    ..sort((a, b) => b.date.compareTo(a.date));

                  if (filtered.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16.0),
                      child: Center(
                        child: Text('Chưa có lịch sử giao dịch',
                            style:
                                TextStyle(color: Colors.black38, fontSize: 12)),
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
                      final isImport = tx.type.name == 'import';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: isImport
                                ? Colors.green.withOpacity(0.08)
                                : Colors.red.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isImport ? Icons.call_received : Icons.call_made,
                            color: isImport ? Colors.green : Colors.red,
                            size: 16,
                          ),
                        ),
                        title: Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(tx.date)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: Colors.black87),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tx.note.isNotEmpty
                                  ? (tx.note.contains('Chuyển') ||
                                          tx.note.contains('Nhận')
                                      ? tx.note
                                      : (isImport
                                          ? tx.note
                                          : 'Bán hàng (Mã đơn: ${tx.note})'))
                                  : (isImport ? 'Nhập kho' : 'Xuất kho'),
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 11),
                            ),
                            Text(
                              '${l10n.performedBy}: ${tx.createdByName ?? tx.createdBy ?? '—'}',
                              style: const TextStyle(
                                  color: Colors.black54, fontSize: 11),
                            ),
                            if (tx.importPrice != null && (ref.watch(authProvider)?.canViewCostPrice ?? false))
                              Text(
                                'Giá nhập: ${format.format(tx.importPrice)} đ',
                                style: const TextStyle(
                                    color: Colors.black45, fontSize: 11),
                              ),
                          ],
                        ),
                        trailing: Text(
                          '${isImport ? "+" : "-"}${tx.quantity}',
                          style: TextStyle(
                            color: isImport ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w800,
                            fontSize: 13,
                          ),
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

  void _showBranchStockBottomSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(16),
          topRight: Radius.circular(16),
        ),
      ),
      builder: (context) {
        return Consumer(
          builder: (context, ref, child) {
            final branches = ref.watch(branchesProvider);
            final b1Name = branches.firstWhere((b) => b.id == 'branch_1').name;
            final b2Name = branches.firstWhere((b) => b.id == 'branch_2').name;

            return Container(
              padding: const EdgeInsets.only(
                  top: 16, bottom: 32, left: 16, right: 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Tồn kho chi tiết',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      )
                    ],
                  ),
                  const Divider(color: AppColors.divider),
                  ListTile(
                    title: Text(b1Name, style: const TextStyle(fontSize: 14)),
                    trailing: Text(
                      '${_currentProduct.branchStocks['branch_1'] ?? 0}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.dividerLight),
                  ListTile(
                    title: Text(b2Name, style: const TextStyle(fontSize: 14)),
                    trailing: Text(
                      '${_currentProduct.branchStocks['branch_2'] ?? 0}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.dividerLight),
                  ListTile(
                    title: const Text('Tổng cộng toàn hệ thống',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.bold)),
                    trailing: Text(
                      '${_currentProduct.stock}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // Toggle "Bán trực tiếp" directly from details
  void _toggleSellDirectly(bool v) async {
    setState(() {
      _sellDirectly = v;
      _isLoading = true;
    });

    try {
      final updated = _currentProduct.copyWith(
        type: v ? 'Hàng hóa' : 'Dịch vụ', // Map direct selling switch to type
      );
      await ref.read(productRepositoryProvider).upsert(updated);
      ref.invalidate(productListProvider);
      setState(() {
        _currentProduct = updated;
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Đã cập nhật cấu hình bán trực tiếp!'),
            backgroundColor: Colors.green),
      );
    } catch (e) {
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
          color: Colors.white,
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
                  _buildEditField(
                      _stockController, 'Tồn kho', Icons.inventory_2,
                      isNumber: true, hint: '0'),
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
                            style:
                                TextStyle(fontSize: 12, color: Colors.black87),
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

        // Switch sell directly
        Card(
          color: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: const BorderSide(color: AppColors.borderLight),
          ),
          child: SwitchListTile(
            value: _sellDirectly,
            onChanged: (v) => setState(() => _sellDirectly = v),
            title: const Text(
              'Bán trực tiếp',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.black87),
            ),
            subtitle: const Text('Cho phép sản phẩm bán trực tiếp tại quầy POS',
                style: TextStyle(fontSize: 11)),
            activeColor: AppColors.primary,
          ),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  String? _newOnlineImageUrl;

  Widget _buildImageEditorCard() {
    final hasNewOnline = _newOnlineImageUrl != null && _newOnlineImageUrl!.isNotEmpty;
    final showCurrentImage = _currentProduct.imageUrl != null &&
        _currentProduct.imageUrl!.isNotEmpty &&
        !_clearCurrentImage &&
        _newImageFile == null &&
        _newImageBytes == null &&
        !hasNewOnline;

    final hasAnyImage = showCurrentImage ||
        _newImageFile != null ||
        _newImageBytes != null ||
        hasNewOnline;

    return GestureDetector(
      onTap: _showImageSourceSheet,
      child: Card(
        color: Colors.white,
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
                            ? Image.network(
                                _newOnlineImageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  color: Colors.grey.shade100,
                                  child: const Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.broken_image,
                                            color: Colors.redAccent, size: 36),
                                        SizedBox(height: 4),
                                        Text('Link ảnh không hợp lệ',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.redAccent)),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : _newImageFile != null
                                ? Image.file(_newImageFile!, fit: BoxFit.cover)
                                : _newImageBytes != null
                                    ? Image.memory(_newImageBytes!,
                                        fit: BoxFit.cover)
                                    : Image.network(_currentProduct.imageUrl!,
                                        fit: BoxFit.cover),
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
                          backgroundColor: Colors.black.withOpacity(0.6),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 16),
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
                          color: Colors.black.withOpacity(0.6),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.edit,
                                color: Colors.white, size: 12),
                            const SizedBox(width: 4),
                            Text(
                              hasNewOnline
                                  ? 'Link Online'
                                  : (_newImageFile != null || _newImageBytes != null
                                      ? 'Ảnh mới'
                                      : 'Ảnh hiện tại'),
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    )
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_a_photo_outlined,
                          color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Thay đổi ảnh sản phẩm',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Camera · Thư viện · Dán link web',
                      style: TextStyle(fontSize: 11, color: Colors.black45),
                    )
                  ],
                ),
        ),
      ),
    );
  }

  void _showImageSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                    backgroundColor: Color(0xFFFFF3E0),
                    child: Icon(Icons.camera_alt, color: Colors.orange, size: 20),
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
                    backgroundColor: Color(0xFFE6FFFA),
                    child: Icon(Icons.link, color: Colors.teal, size: 20),
                  ),
                  title: const Text('Nhập / Dán Link ảnh Online',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Dán link ảnh từ Google Images hoặc website'),
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

  void _pickImageFromCamera() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _newImageBytes = bytes;
            _newImageFile = null;
            _newOnlineImageUrl = null;
            _clearCurrentImage = true;
          });
        } else {
          setState(() {
            _newImageFile = File(pickedFile.path);
            _newImageBytes = null;
            _newOnlineImageUrl = null;
            _clearCurrentImage = true;
          });
        }
      }
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
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (pickedFile != null) {
        if (kIsWeb) {
          final bytes = await pickedFile.readAsBytes();
          setState(() {
            _newImageBytes = bytes;
            _newImageFile = null;
            _newOnlineImageUrl = null;
            _clearCurrentImage = true;
          });
        } else {
          setState(() {
            _newImageFile = File(pickedFile.path);
            _newImageBytes = null;
            _newOnlineImageUrl = null;
            _clearCurrentImage = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chọn ảnh: $e')),
        );
      }
    }
  }

  void _showImageUrlDialog() {
    final urlController =
        TextEditingController(text: _newOnlineImageUrl ?? '');
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
                style: TextStyle(fontSize: 13, color: Colors.black54),
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
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Xác nhận'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEditField(
      TextEditingController controller, String label, IconData icon,
      {bool required = false,
      bool isNumber = false,
      String? hint}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.black45),
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
          prefixIcon: Icon(Icons.category, color: Colors.black45),
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
                      ? Colors.black87
                      : Colors.black38,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black54),
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
      var current = selected;
      while (current.parentId != null) {
        final parent = categories.firstWhere(
          (c) => c.id == current.parentId,
          orElse: () => Category(id: '', name: ''),
        );
        if (parent.id.isEmpty) break;
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
          prefixIcon: Icon(Icons.business, color: Colors.black45),
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
                      ? Colors.black87
                      : Colors.black38,
                  fontSize: 14,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black54),
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
      color: Colors.white,
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
                color: Colors.black87)),
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
      color: Colors.white,
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
      color: Colors.white,
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
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            title: Text('${attr['name']}: ${attr['value']}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            trailing: IconButton(
              icon:
                  const Icon(Icons.delete_outline, color: Colors.red, size: 18),
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
        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            title: Text('${unit['name']}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: Text('Giá bán: ${unit['price']} đ'),
            trailing: IconButton(
              icon:
                  const Icon(Icons.delete_outline, color: Colors.red, size: 18),
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
                if (name.isNotEmpty) {
                  setState(() {
                    _units.add({'name': name, 'price': price});
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

      // Handle image deletion and upload
      if (_clearCurrentImage) {
        if (_currentProduct.imageUrl != null &&
            _currentProduct.imageUrl!.isNotEmpty &&
            !_currentProduct.imageUrl!.startsWith('http')) {
          try {
            await FirebaseStorage.instance
                .refFromURL(_currentProduct.imageUrl!)
                .delete();
          } catch (_) {}
        }
        imageUrl = null;
      }

      if (_newOnlineImageUrl != null && _newOnlineImageUrl!.isNotEmpty) {
        imageUrl = _newOnlineImageUrl;
      } else if (_newImageFile != null || _newImageBytes != null) {
        final storageRef = FirebaseStorage.instance
            .ref('stores/$storeId/products/${_currentProduct.id}.jpg');
        if (kIsWeb && _newImageBytes != null) {
          await storageRef.putData(_newImageBytes!);
        } else if (_newImageFile != null) {
          await storageRef.putFile(_newImageFile!);
        }
        imageUrl = await storageRef.getDownloadURL();
      }

      // Convert attributes list to model field string
      final modelString =
          _attributes.map((a) => '${a['name']}:${a['value']}').join(', ');
      final categoryName = _selectedCategory?.name ?? _currentProduct.category;

      final updatedProduct = Product(
        id: _currentProduct.id,
        name: _nameController.text.trim(),
        code: _codeController.text.trim(),
        barcode: _barcodeController.text.trim().isEmpty
            ? null
            : _barcodeController.text.trim(),
        brand: _brandController.text.trim(),
        model: modelString,
        price: price,
        costPrice: costPrice,
        branchStocks: {
          'branch_1': stock,
          'branch_2': 0,
        },
        category: categoryName,
        category3Levels: _selectedCategoryPath,
        unit: _units.isNotEmpty ? _units.first['name'] : _currentProduct.unit,
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
        type: _sellDirectly ? 'Hàng hóa' : 'Dịch vụ',
        isCombo: _currentProduct.isCombo,
        comboComponents: _currentProduct.comboComponents,
      );

      await ref.read(productRepositoryProvider).upsert(updatedProduct);
      ref.invalidate(productListProvider);

      if (mounted) {
        setState(() {
          _currentProduct = updatedProduct;
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.updated), backgroundColor: Colors.green),
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
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
      // Delete image from storage first
      if (_currentProduct.imageUrl != null &&
          _currentProduct.imageUrl!.isNotEmpty) {
        try {
          await FirebaseStorage.instance
              .refFromURL(_currentProduct.imageUrl!)
              .delete();
        } catch (_) {}
      }

      await ref.read(productRepositoryProvider).delete(_currentProduct.id);
      ref.invalidate(productListProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.updated), backgroundColor: Colors.green),
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
