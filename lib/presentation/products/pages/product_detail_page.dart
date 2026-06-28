import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/loading_indicator.dart';

import '../../inventories/pages/inter_store_transfer_page.dart';
import '../../../application/products/products_providers.dart';
import '../../../application/inventory/inventory_providers.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../core/constants/product_categories.dart';
import '../../../domain/entities/product.dart';
import '../../../core/constants/app_constants.dart';

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

  late TextEditingController _nameController;
  late TextEditingController _codeController;
  late TextEditingController _barcodeController;
  late TextEditingController _brandController;
  late TextEditingController _modelController;
  late TextEditingController _priceController;
  late TextEditingController _costPriceController;
  late TextEditingController _branch1StockController;
  late TextEditingController _branch2StockController;
  late String _selectedCategory;

  @override
  void initState() {
    super.initState();
    _currentProduct = widget.product;
    _initializeControllers();
  }

  void _initializeControllers() {
    _nameController = TextEditingController(text: _currentProduct.name);
    _codeController = TextEditingController(text: _currentProduct.code);
    _barcodeController = TextEditingController(text: _currentProduct.barcode ?? '');
    _brandController = TextEditingController(text: _currentProduct.brand);
    _modelController = TextEditingController(text: _currentProduct.model);
    _priceController = TextEditingController(text: _currentProduct.price.toStringAsFixed(0));
    _costPriceController = TextEditingController(text: _currentProduct.costPrice.toStringAsFixed(0));
    _branch1StockController = TextEditingController(text: (_currentProduct.branchStocks['branch_1'] ?? 0).toString());
    _branch2StockController = TextEditingController(text: (_currentProduct.branchStocks['branch_2'] ?? 0).toString());
    _selectedCategory = _currentProduct.category;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _barcodeController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _priceController.dispose();
    _costPriceController.dispose();
    _branch1StockController.dispose();
    _branch2StockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final currencyFormat = NumberFormat('#,###', 'vi_VN');

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: Text(_isEditing ? l10n.editProduct : l10n.productDetail),
        backgroundColor: Colors.white,
        actions: [
          if (!_isEditing) ...[
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              onPressed: () {
                Navigator.of(context).push(MaterialPageRoute(
                  builder: (context) => InterStoreTransferPage(product: _currentProduct),
                ));
              },
              tooltip: l10n.transferProduct,
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => setState(() => _isEditing = true),
              tooltip: l10n.edit,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              onPressed: _showDeleteDialog,
              tooltip: l10n.delete,
            ),
          ] else ...[
            IconButton(
              icon: const Icon(Icons.save_outlined),
              onPressed: _isLoading ? null : _saveProduct,
              tooltip: l10n.save,
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
          ? const Center(child: LoadingIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isEditing) ...[
                    // MÀN HÌNH XEM CHI TIẾT
                    _buildProductHeader(context),
                    const SizedBox(height: 12),
                    _buildBasicInfoCard(context, currencyFormat),
                    const SizedBox(height: 12),
                    _buildBranchStockCard(context),
                    const SizedBox(height: 12),
                    _buildAssistantCard(context),
                    const SizedBox(height: 12),
                    _buildStockCardSection(context, currencyFormat),
                  ] else ...[
                    // MÀN HÌNH CHỈNH SỬA
                    _buildEditForm(l10n),
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
        border: Border.all(color: const Color(0xFFE1E2E4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: const Color(0xFF0067AC).withOpacity(0.08),
            child: Icon(
              ProductCategories.getCategoryIcon(_currentProduct.category),
              color: const Color(0xFF0067AC),
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _currentProduct.name,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_currentProduct.brand} • ${_currentProduct.model}',
                  style: const TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Thẻ thông tin tài chính & định danh cơ bản
  Widget _buildBasicInfoCard(BuildContext context, NumberFormat format) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E2E4)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          _buildDetailRow('Mã hàng', _currentProduct.code, true),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          _buildDetailRow('Mã vạch', _currentProduct.barcode ?? '—', true),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          _buildDetailRow('Giá vốn', '${format.format(_currentProduct.costPrice)} đ', false),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          _buildDetailRow('Giá bán', '${format.format(_currentProduct.price)} đ', false),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          _buildDetailRow('Nhóm hàng', _currentProduct.category, false),
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
          Text(label, style: const TextStyle(color: Colors.black54, fontSize: 14)),
          Row(
            children: [
              Text(
                value,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
              ),
              if (isCopyable && value != '—') ...[
                const SizedBox(width: 6),
                const Icon(Icons.copy_outlined, size: 14, color: Colors.black38),
              ]
            ],
          )
        ],
      ),
    );
  }

  // Thẻ tồn kho chi nhánh
  Widget _buildBranchStockCard(BuildContext context) {
    return InkWell(
      onTap: () => _showBranchStockBottomSheet(context),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE1E2E4)),
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
                  style: TextStyle(fontSize: 14, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                Text(
                  'Tổng tồn: ${_currentProduct.stock}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                )
              ],
            ),
            Row(
              children: const [
                Text(
                  'Chi tiết',
                  style: TextStyle(color: Color(0xFF0067AC), fontSize: 13, fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 4),
                Icon(Icons.chevron_right, color: Color(0xFF0067AC), size: 18),
              ],
            )
          ],
        ),
      ),
    );
  }

  // Thẻ Trợ lý phân tích (KiotViet Assistant Mock)
  Widget _buildAssistantCard(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E2E4)),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.psychology_outlined, color: Colors.teal),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trợ lý ${AppConstants.appName}',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Xem phân tích hiệu quả bán hàng',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  )
                ],
              )
            ],
          ),
          const Icon(Icons.chevron_right, color: Colors.black38)
        ],
      ),
    );
  }

  // Thẻ kho (Nhật ký giao dịch)
  Widget _buildStockCardSection(BuildContext context, NumberFormat format) {
    return Consumer(
      builder: (context, ref, child) {
        final txAsync = ref.watch(transactionsByProductProvider(_currentProduct.id));
        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE1E2E4)),
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
                  ),
                  SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('Tất cả', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 1, label: Text('Nhập', style: TextStyle(fontSize: 11))),
                      ButtonSegment(value: 2, label: Text('Xuất', style: TextStyle(fontSize: 11))),
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
              const SizedBox(height: 16),
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
                      padding: EdgeInsets.symmetric(vertical: 24.0),
                      child: Center(
                        child: Text('Chưa có lịch sử giao dịch', style: TextStyle(color: Colors.black38)),
                      ),
                    );
                  }

                  return ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF0F0F0)),
                    itemBuilder: (context, index) {
                      final tx = filtered[index];
                      final isImport = tx.type.name == 'import';
                      return ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: isImport ? Colors.green.withOpacity(0.08) : Colors.red.withOpacity(0.08),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isImport ? Icons.call_received : Icons.call_made,
                            color: isImport ? Colors.green : Colors.red,
                            size: 18,
                          ),
                        ),
                        title: Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(tx.date)}',
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Colors.black87),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isImport ? 'Nhập kho hàng loạt' : 'Bán hàng (Đơn ${tx.note})',
                              style: const TextStyle(color: Colors.black54, fontSize: 11),
                            ),
                            if (tx.importPrice != null)
                              Text(
                                'Giá nhập: ${format.format(tx.importPrice)} đ',
                                style: const TextStyle(color: Colors.black45, fontSize: 11),
                              ),
                          ],
                        ),
                        trailing: Text(
                          '${isImport ? "+" : "-"}${tx.quantity}',
                          style: TextStyle(
                            color: isImport ? Colors.green : Colors.red,
                            fontWeight: FontWeight.w800,
                            fontSize: 14,
                          ),
                        ),
                      );
                    },
                  );
                },
                loading: () => const Center(child: LoadingIndicator()),
                error: (e, _) => Center(child: Text('Lỗi tải thẻ kho: $e')),
              )
            ],
          ),
        );
      },
    );
  }

  // Bottom Sheet hiển thị tồn kho chi tiết
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
        final currentStoreId = ref.read(currentStoreIdProvider);
        final mockBranches = getMockBranches(currentStoreId);
        final b1Name = mockBranches.firstWhere((b) => b.id == 'branch_1').name;
        final b2Name = mockBranches.firstWhere((b) => b.id == 'branch_2').name;

        return Container(
          padding: const EdgeInsets.only(top: 16, bottom: 32, left: 16, right: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tồn kho chi tiết',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  )
                ],
              ),
              const Divider(color: Color(0xFFEEEEEE)),
              ListTile(
                title: Text(b1Name, style: const TextStyle(fontSize: 14)),
                trailing: Text(
                  '${_currentProduct.branchStocks['branch_1'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
              ListTile(
                title: Text(b2Name, style: const TextStyle(fontSize: 14)),
                trailing: Text(
                  '${_currentProduct.branchStocks['branch_2'] ?? 0}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              const Divider(height: 1, color: Color(0xFFF0F0F0)),
              ListTile(
                title: const Text('Tổng cộng toàn hệ thống', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                trailing: Text(
                  '${_currentProduct.stock}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0067AC)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // MÀN HÌNH CHỈNH SỬA SẢN PHẨM
  Widget _buildEditForm(AppLocalizations l10n) {
    return Form(
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE1E2E4)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildEditField(_nameController, 'Tên sản phẩm', Icons.label),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildEditField(_codeController, 'Mã hàng SKU', Icons.qr_code)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildEditField(_barcodeController, 'Mã vạch (Barcode)', Icons.barcode_reader, required: false)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildEditField(_brandController, l10n.brand, Icons.business)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildEditField(_modelController, l10n.model, Icons.model_training)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildEditField(_costPriceController, 'Giá vốn', Icons.shopping_basket_outlined, isNumber: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildEditField(_priceController, 'Giá bán', Icons.attach_money, isNumber: true)),
                  ],
                ),
                const SizedBox(height: 12),
                _buildCategoryDropdown(l10n),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Cài đặt tồn kho cho các chi nhánh trực tiếp khi edit
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE1E2E4)),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cập nhật tồn kho chi nhánh',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.black87),
                ),
                const SizedBox(height: 12),
                _buildEditField(_branch1StockController, 'Cửa hàng Hà Nội', Icons.store, isNumber: true),
                const SizedBox(height: 12),
                _buildEditField(_branch2StockController, 'Cửa hàng TP.HCM', Icons.store, isNumber: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEditField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool isNumber = false,
    bool required = true,
  }) {
    final l10n = AppLocalizations.of(context)!;

    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) {
          return '${l10n.pleaseEnter} $label';
        }
        if (isNumber && value != null && value.isNotEmpty) {
          final number = double.tryParse(value);
          if (number == null) {
            return l10n.pleaseEnterValidNumber;
          }
        }
        return null;
      },
    );
  }

  Widget _buildCategoryDropdown(AppLocalizations l10n) {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      decoration: const InputDecoration(
        labelText: 'Nhóm hàng',
        prefixIcon: Icon(Icons.category),
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
      items: ProductCategories.categories.map((category) {
        return DropdownMenuItem(
          value: category,
          child: Row(
            children: [
              Icon(ProductCategories.getCategoryIcon(category)),
              const SizedBox(width: 8),
              Text(category),
            ],
          ),
        );
      }).toList(),
      onChanged: (value) {
        if (value != null) {
          setState(() => _selectedCategory = value);
        }
      },
    );
  }

  String _formatPrice(double price) {
    return NumberFormat.currency(locale: 'vi_VN', symbol: 'đ').format(price);
  }

  Future<void> _saveProduct() async {
    final l10n = AppLocalizations.of(context)!;

    // Validate form
    if (_nameController.text.trim().isEmpty ||
        _codeController.text.trim().isEmpty ||
        _brandController.text.trim().isEmpty ||
        _modelController.text.trim().isEmpty ||
        _priceController.text.trim().isEmpty ||
        _costPriceController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseFillAllField)),
      );
      return;
    }

    final price = double.tryParse(_priceController.text.trim());
    final costPrice = double.tryParse(_costPriceController.text.trim());
    final branch1Stock = int.tryParse(_branch1StockController.text.trim()) ?? 0;
    final branch2Stock = int.tryParse(_branch2StockController.text.trim()) ?? 0;

    if (price == null || costPrice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.pleaseEnterValidNumber)),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final updatedProduct = Product(
        id: _currentProduct.id,
        name: _nameController.text.trim(),
        code: _codeController.text.trim(),
        barcode: _barcodeController.text.trim().isEmpty ? null : _barcodeController.text.trim(),
        brand: _brandController.text.trim(),
        model: _modelController.text.trim(),
        price: price,
        costPrice: costPrice,
        branchStocks: {
          'branch_1': branch1Stock,
          'branch_2': branch2Stock,
        },
        category: _selectedCategory,
      );

      await ref.read(productRepositoryProvider).upsert(updatedProduct);

      // Invalidate product providers to refresh UI
      ref.invalidate(productListProvider);

      if (mounted) {
        setState(() {
          _currentProduct = updatedProduct;
          _isEditing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.updated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
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
      await ref.read(productRepositoryProvider).delete(_currentProduct.id);
      ref.invalidate(productListProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.updated)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
