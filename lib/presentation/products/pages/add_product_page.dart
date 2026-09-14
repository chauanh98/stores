import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/products/categories_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../core/utils/code_generator_helper.dart';
import '../../../core/utils/combo_helper.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/combo_component.dart';
import '../../../domain/entities/product.dart';
import '../../../domain/entities/product_unit.dart';
import '../widgets/sample_image_picker_dialog.dart';
import 'select_brand_page.dart';
import 'select_category_page.dart';

class AddProductPage extends ConsumerStatefulWidget {
  final Product? product;
  final Product? initialProduct;

  const AddProductPage({
    super.key,
    this.product,
    this.initialProduct,
  });

  Product? get productToUse => product ?? initialProduct;

  @override
  ConsumerState<AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends ConsumerState<AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  final _barcodeController = TextEditingController();
  final _nameController = TextEditingController();
  final _brandController = TextEditingController();
  final _costPriceController = TextEditingController();
  final _priceController = TextEditingController();
  final _stockController = TextEditingController();
  final _baseUnitController = TextEditingController(text: 'Cái');

  Category? _selectedCategory;
  String _selectedCategoryPath = '';

  // Image Upload State
  File? _selectedImageFile;
  Uint8List? _imageBytes;
  String? _onlineImageUrl;
  bool _isLoading = false;

  // Extra Sub-Sections Toggles & Controllers
  bool _showDescription = false;
  final _descriptionController = TextEditingController();

  final _minStockController = TextEditingController();
  final _maxStockController = TextEditingController();

  bool _showOtherInfo = false;
  final _noteTemplateController = TextEditingController();
  final _componentsController = TextEditingController();

  // Combo Product States
  bool _isCombo = false;
  final List<ComboComponent> _comboComponents = [];

  // Attributes & Multi-Units states
  final List<Map<String, String>> _attributes = [];
  final List<ProductUnit> _units = [];
  bool _sellDirectly = true;

  @override
  void initState() {
    super.initState();
    final p = widget.productToUse;
    if (p != null) {
      _nameController.text = p.name;
      _codeController.text = p.code;
      _barcodeController.text = p.barcode ?? '';
      _brandController.text = p.brand ?? '';
      _priceController.text =
          p.price > 0 ? p.price.toStringAsFixed(0) : '';
      _costPriceController.text =
          p.costPrice > 0 ? p.costPrice.toStringAsFixed(0) : '';
      _stockController.text = p.stock.toString();
      _baseUnitController.text = p.unit ?? 'Cái';
      _units.addAll(p.units);
      if (p.minStock != null) _minStockController.text = p.minStock.toString();
      if (p.maxStock != null) _maxStockController.text = p.maxStock.toString();
      if (p.description != null && p.description!.isNotEmpty) {
        _descriptionController.text = p.description!;
        _showDescription = true;
      }
      if (p.noteTemplate != null && p.noteTemplate!.isNotEmpty) {
        _noteTemplateController.text = p.noteTemplate!;
        _showOtherInfo = true;
      }
      if (p.components != null && p.components!.isNotEmpty) {
        _componentsController.text = p.components!;
        _showOtherInfo = true;
      }
      _selectedCategoryPath = p.category3Levels ?? p.category;
      _onlineImageUrl = p.imageUrl;
      _isCombo = p.isCombo;
      _comboComponents.addAll(p.comboComponents);
      _sellDirectly = p.allowSale;
      if (p.model != null && p.model!.isNotEmpty) {
        try {
          final pairs = p.model!.split(', ');
          for (final pair in pairs) {
            final parts = pair.split(':');
            if (parts.length == 2) {
              _attributes.add({'name': parts[0], 'value': parts[1]});
            }
          }
        } catch (_) {}
      }
    } else {
      _baseUnitController.text = 'Cái';
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _barcodeController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    _costPriceController.dispose();
    _priceController.dispose();
    _stockController.dispose();
    _baseUnitController.dispose();
    _descriptionController.dispose();
    _minStockController.dispose();
    _maxStockController.dispose();
    _noteTemplateController.dispose();
    _componentsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    final canManageProducts = user?.canManageProducts ?? false;
    final canViewCostPrice = user?.canViewCostPrice ?? false;
    final isEditing = widget.productToUse != null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isEditing ? 'Chỉnh sửa sản phẩm' : 'Hàng hóa mới',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed:
                (canManageProducts && !_isLoading) ? _saveProduct : null,
            child: Text(
              'Lưu',
              style: TextStyle(
                color: canManageProducts ? AppColors.primary : Colors.grey,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Permission Warning Banner if Staff
                    if (!canManageProducts)
                      Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.lock_outline,
                                color: Colors.amber, size: 22),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Bạn không có quyền quản lý hàng hóa (chỉ xem). Vui lòng liên hệ Quản lý để thao tác.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // 1. Image Picker Top Card
                    _buildImagePickerCard(enabled: canManageProducts),
                    const SizedBox(height: 16),

                    // 2. Core Fields Card
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
                            _buildField(
                              _nameController,
                              'Tên hàng *',
                              Icons.label,
                              required: true,
                              enabled: canManageProducts,
                            ),
                            const SizedBox(height: 16),
                            _buildCodeField(enabled: canManageProducts),
                            const SizedBox(height: 16),
                            _buildBarcodeField(enabled: canManageProducts),
                            const SizedBox(height: 16),
                            _buildCategorySelector(enabled: canManageProducts),
                            const SizedBox(height: 16),
                            _buildBrandSelector(enabled: canManageProducts),
                            const SizedBox(height: 16),
                            // Cost Price: Role-guarded (Only Supervisor can view/edit)
                            if (canViewCostPrice) ...[
                              _buildField(
                                _costPriceController,
                                'Giá vốn',
                                Icons.download,
                                isNumber: true,
                                hint: '0',
                                enabled: canManageProducts,
                              ),
                              const SizedBox(height: 16),
                            ],
                            _buildField(
                              _priceController,
                              'Giá bán',
                              Icons.upload,
                              isNumber: true,
                              hint: '0',
                              enabled: canManageProducts,
                            ),
                            if (!_isCombo) ...[
                              const SizedBox(height: 16),
                              _buildField(
                                _stockController,
                                'Tồn kho',
                                Icons.inventory_2,
                                isNumber: true,
                                hint: '0',
                                enabled: canManageProducts,
                              ),
                            ] else ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color:
                                          AppColors.primary.withOpacity(0.2)),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: AppColors.primary, size: 20),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Tồn kho của Combo không cần nhập, hệ thống sẽ tự động tính dựa trên số lượng linh kiện thành phần.',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.black87),
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

                    // 3. Units Conversion Management Card
                    _buildUnitsSection(
                        enabled: canManageProducts,
                        canViewCostPrice: canViewCostPrice),
                    const SizedBox(height: 16),

                    // 4. Min / Max Stock Limits Card
                    _buildStockLimitsSection(enabled: canManageProducts),
                    const SizedBox(height: 16),

                    // 5. Extra Actions (Description, Attributes, Other Info)
                    _buildExtraActionRow(
                      icon: Icons.notes,
                      label: 'Thêm mô tả',
                      onTap: () =>
                          setState(() => _showDescription = !_showDescription),
                      isToggled: _showDescription,
                    ),
                    if (_showDescription) ...[
                      const SizedBox(height: 8),
                      _buildCollapsibleInput(
                        _descriptionController,
                        'Nhập mô tả sản phẩm...',
                        maxLines: 3,
                        enabled: canManageProducts,
                      ),
                    ],
                    const SizedBox(height: 8),

                    _buildExtraActionRow(
                      icon: Icons.style,
                      label: 'Thêm thuộc tính (Màu sắc, kích thước...)',
                      onTap: canManageProducts ? _showAttributesDialog : () {},
                      trailingWidget: _attributes.isNotEmpty
                          ? Chip(
                              label: Text('${_attributes.length} thuộc tính'))
                          : null,
                    ),
                    if (_attributes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildAttributesList(enabled: canManageProducts),
                    ],
                    const SizedBox(height: 8),

                    _buildExtraActionRow(
                      icon: Icons.info_outline,
                      label: 'Thêm thông tin khác',
                      onTap: () =>
                          setState(() => _showOtherInfo = !_showOtherInfo),
                      isToggled: _showOtherInfo,
                    ),
                    if (_showOtherInfo) ...[
                      const SizedBox(height: 8),
                      _buildOtherInfoInputs(enabled: canManageProducts),
                    ],
                    const SizedBox(height: 16),

                    // Combo Product Card
                    _buildComboSectionCard(enabled: canManageProducts),
                    const SizedBox(height: 16),

                    // Direct Selling Switch (Cho phép bán / Ngừng kinh doanh)
                    Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: AppColors.borderLight),
                      ),
                      child: SwitchListTile(
                        value: _sellDirectly,
                        onChanged: canManageProducts
                            ? (v) => setState(() => _sellDirectly = v)
                            : null,
                        title: const Text(
                          'Cho phép bán',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.black87),
                        ),
                        subtitle: Text(
                          _sellDirectly
                              ? 'Đang kinh doanh (Hiển thị trên POS và cho phép bán hàng)'
                              : 'Ngừng kinh doanh (Tự động ẩn khỏi màn hình POS)',
                          style: TextStyle(
                            fontSize: 11,
                            color: _sellDirectly
                                ? Colors.green.shade700
                                : Colors.red.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        activeColor: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
    );
  }

  // SKU code field with 1-click auto-generation
  Widget _buildCodeField({required bool enabled}) {
    return TextFormField(
      controller: _codeController,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: 'Mã hàng (SKU)',
        hintText: 'Tự động tạo hoặc nhập thủ công',
        prefixIcon: const Icon(Icons.tag, color: Colors.black45),
        suffixIcon: IconButton(
          icon: const Icon(Icons.auto_awesome, color: AppColors.primary),
          tooltip: 'Tự động tạo mã SKU',
          onPressed: enabled ? _generateNextCode : null,
        ),
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  void _generateNextCode() {
    final products = ref.read(productListProvider).value ?? [];
    final existingCodes = products.map((p) => p.code).toList();
    final nextCode = CodeGeneratorHelper.generateNextProductCode(existingCodes);
    setState(() {
      _codeController.text = nextCode;
    });
  }

  // Barcode field with Scan button
  Widget _buildBarcodeField({required bool enabled}) {
    return TextFormField(
      controller: _barcodeController,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: 'Mã vạch',
        hintText: 'Quét hoặc nhập mã vạch',
        prefixIcon: const Icon(Icons.qr_code, color: Colors.black45),
        suffixIcon: IconButton(
          icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
          tooltip: 'Quét mã vạch',
          onPressed: enabled ? _scanBarcode : null,
        ),
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  void _scanBarcode() async {
    final scanController = TextEditingController(text: _barcodeController.text);
    final scanned = await showDialog<String>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.qr_code_scanner, color: AppColors.primary),
            SizedBox(width: 8),
            Text('Quét mã vạch',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Nhập hoặc quét mã vạch từ đầu đọc mã vạch:',
                style: TextStyle(fontSize: 13, color: Colors.black54)),
            const SizedBox(height: 12),
            TextField(
              controller: scanController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Mã vạch (Barcode)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.qr_code),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogCtx, scanController.text.trim()),
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Xác nhận'),
          ),
        ],
      ),
    );

    if (scanned != null && mounted) {
      setState(() {
        _barcodeController.text = scanned;
      });
    }
  }

  // Brand Selector with modal navigation
  Widget _buildBrandSelector({required bool enabled}) {
    return Row(
      children: [
        Expanded(
          child: _buildField(
            _brandController,
            'Thương hiệu',
            Icons.business,
            enabled: enabled,
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filledTonal(
          icon: const Icon(Icons.search, size: 20),
          tooltip: 'Chọn thương hiệu',
          onPressed: enabled ? _navigateToBrandSelect : null,
        ),
      ],
    );
  }

  void _navigateToBrandSelect() async {
    final selected = await Navigator.push<String>(
      context,
      MaterialPageRoute(
        builder: (context) =>
            SelectBrandPage(initialBrand: _brandController.text.trim()),
      ),
    );

    if (selected != null && mounted) {
      setState(() {
        _brandController.text = selected;
      });
    }
  }

  // Units Conversion Section
  Widget _buildUnitsSection(
      {required bool enabled, required bool canViewCostPrice}) {
    final format = NumberFormat('#,###', 'vi_VN');
    final baseUnitName = _baseUnitController.text.trim().isNotEmpty
        ? _baseUnitController.text.trim()
        : 'Cái';

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.straighten,
                        color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Đơn vị tính & Quy đổi',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    ),
                  ],
                ),
                if (enabled)
                  TextButton.icon(
                    onPressed: () => _showAddEditUnitDialog(
                        canViewCostPrice: canViewCostPrice),
                    icon: const Icon(Icons.add_circle_outline, size: 16),
                    label: const Text('Thêm ĐVT quy đổi',
                        style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _baseUnitController,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Đơn vị cơ bản (Mặc định) *',
                hintText: 'Ví dụ: Cái, Lon, Chai, Hộp...',
                prefixIcon:
                    Icon(Icons.check_box_outlined, color: Colors.black45),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            if (_units.isNotEmpty) ...[
              const Text(
                'Danh sách đơn vị quy đổi:',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: Colors.black87),
              ),
              const SizedBox(height: 8),
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _units.length,
                separatorBuilder: (_, __) =>
                    const Divider(height: 1, color: AppColors.borderLight),
                itemBuilder: (context, index) {
                  final u = _units[index];
                  return ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    title: Text(
                      u.unitName,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Text(
                      '1 ${u.unitName} = ${u.conversionRate} $baseUnitName • Giá bán: ${format.format(u.price)} đ'
                      '${u.barcode != null && u.barcode!.isNotEmpty ? ' • Barcode: ${u.barcode}' : ''}'
                      '${u.code != null && u.code!.isNotEmpty ? ' • SKU: ${u.code}' : ''}',
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                    trailing: enabled
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18, color: AppColors.primary),
                                onPressed: () => _showAddEditUnitDialog(
                                  unitToEdit: u,
                                  editIndex: index,
                                  canViewCostPrice: canViewCostPrice,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    size: 18, color: Colors.red),
                                onPressed: () {
                                  setState(() {
                                    _units.removeAt(index);
                                  });
                                },
                              ),
                            ],
                          )
                        : null,
                  );
                },
              ),
            ] else ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Text(
                  'Chưa có đơn vị quy đổi bổ sung. Hàng hóa sẽ chỉ sử dụng đơn vị cơ bản ($baseUnitName).',
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showAddEditUnitDialog({
    ProductUnit? unitToEdit,
    int? editIndex,
    required bool canViewCostPrice,
  }) {
    final nameController =
        TextEditingController(text: unitToEdit?.unitName ?? '');
    final rateController = TextEditingController(
        text: unitToEdit != null ? unitToEdit.conversionRate.toString() : '');
    final priceController = TextEditingController(
        text: unitToEdit != null ? unitToEdit.price.toStringAsFixed(0) : '');
    final costPriceController = TextEditingController(
        text: unitToEdit?.costPrice != null
            ? unitToEdit!.costPrice!.toStringAsFixed(0)
            : '');
    final barcodeController =
        TextEditingController(text: unitToEdit?.barcode ?? '');
    final codeController = TextEditingController(text: unitToEdit?.code ?? '');
    bool isDirectSale = unitToEdit?.isDirectSale ?? true;

    final baseUnitName = _baseUnitController.text.trim().isNotEmpty
        ? _baseUnitController.text.trim()
        : 'Cái';

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                unitToEdit != null ? 'Sửa đơn vị quy đổi' : 'Thêm đơn vị quy đổi',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Tên đơn vị quy đổi *',
                        hintText: 'Ví dụ: Lốc, Thùng, Hộp, Vỉ...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: rateController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: 'Tỷ lệ quy đổi *',
                        hintText: '1 ĐVT = ? $baseUnitName',
                        helperText: 'Số lượng $baseUnitName trong 1 đơn vị này',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Giá bán quy đổi *',
                        hintText: '0',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (canViewCostPrice) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: costPriceController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Giá vốn quy đổi (Tùy chọn)',
                          hintText: '0',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: barcodeController,
                      decoration: const InputDecoration(
                        labelText: 'Mã vạch đơn vị (Barcode)',
                        hintText: 'Tùy chọn',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeController,
                      decoration: const InputDecoration(
                        labelText: 'Mã SKU đơn vị',
                        hintText: 'Tùy chọn',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Bán trực tiếp trên POS',
                          style: TextStyle(fontSize: 13)),
                      value: isDirectSale,
                      activeColor: AppColors.primary,
                      onChanged: (val) =>
                          setDialogState(() => isDirectSale = val),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogCtx),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () {
                    final name = nameController.text.trim();
                    final rate =
                        int.tryParse(rateController.text.trim()) ?? 1;
                    final price =
                        double.tryParse(priceController.text.trim()) ?? 0.0;
                    final costPrice =
                        double.tryParse(costPriceController.text.trim());
                    final barcode = barcodeController.text.trim().isNotEmpty
                        ? barcodeController.text.trim()
                        : null;
                    final code = codeController.text.trim().isNotEmpty
                        ? codeController.text.trim()
                        : null;

                    if (name.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Vui lòng nhập tên đơn vị quy đổi')),
                      );
                      return;
                    }

                    final newUnit = ProductUnit(
                      id: unitToEdit?.id ??
                          'unit_${DateTime.now().millisecondsSinceEpoch}_${_units.length}',
                      unitName: name,
                      conversionRate: rate > 0 ? rate : 1,
                      price: price,
                      costPrice: costPrice,
                      barcode: barcode,
                      code: code,
                      isDirectSale: isDirectSale,
                    );

                    setState(() {
                      if (editIndex != null &&
                          editIndex >= 0 &&
                          editIndex < _units.length) {
                        _units[editIndex] = newUnit;
                      } else {
                        _units.add(newUnit);
                      }
                    });

                    Navigator.pop(dialogCtx);
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: Text(unitToEdit != null ? 'Cập nhật' : 'Thêm'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Min / Max Stock Limits Section
  Widget _buildStockLimitsSection({required bool enabled}) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    color: AppColors.primary, size: 20),
                SizedBox(width: 8),
                Text(
                  'Định mức tồn kho (Cảnh báo Min / Max)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _minStockController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tồn tối thiểu',
                      hintText: 'VD: 5',
                      prefixIcon: Icon(Icons.arrow_downward,
                          color: Colors.orange, size: 18),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: _maxStockController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Tồn tối đa',
                      hintText: 'VD: 200',
                      prefixIcon: Icon(Icons.arrow_upward,
                          color: Colors.blue, size: 18),
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Hệ thống sẽ tự động phát cảnh báo khi lượng tồn kho <= Tồn tối thiểu hoặc vượt quá Tồn tối đa.',
              style: TextStyle(fontSize: 11, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  // Image Picker Top Card
  Widget _buildImagePickerCard({required bool enabled}) {
    final hasImage = _selectedImageFile != null ||
        _imageBytes != null ||
        (_onlineImageUrl != null && _onlineImageUrl!.isNotEmpty);

    return GestureDetector(
      onTap: enabled ? _showImageSourceSheet : null,
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
          child: hasImage
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _onlineImageUrl != null &&
                                _onlineImageUrl!.isNotEmpty
                            ? Image.network(
                                _onlineImageUrl!,
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
                            : _imageBytes != null
                                ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                                : Image.file(_selectedImageFile!,
                                    fit: BoxFit.cover),
                      ),
                    ),
                    if (enabled)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _selectedImageFile = null;
                            _imageBytes = null;
                            _onlineImageUrl = null;
                          }),
                          child: CircleAvatar(
                            radius: 14,
                            backgroundColor: Colors.black.withOpacity(0.6),
                            child: const Icon(Icons.close,
                                color: Colors.white, size: 16),
                          ),
                        ),
                      ),
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
                      'Thêm ảnh sản phẩm',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Camera · Thư viện · Link web · Gợi ý AI',
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
                    backgroundColor: Color(0xFFE8F5E9),
                    child: Icon(Icons.auto_awesome,
                        color: Colors.green, size: 20),
                  ),
                  title: const Text('Gợi ý ảnh mẫu thông minh',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text(
                      'Tự động gợi ý ảnh đẹp theo tên và ngành hàng'),
                  onTap: () async {
                    Navigator.pop(context);
                    final selectedUrl = await SampleImagePickerDialog.show(
                      context,
                      productName: _nameController.text.trim(),
                      category:
                          _selectedCategory?.name ?? _selectedCategoryPath,
                      brand: _brandController.text.trim(),
                      category3Levels: _selectedCategoryPath,
                      isCombo: _isCombo,
                    );
                    if (selectedUrl != null && mounted) {
                      setState(() {
                        _onlineImageUrl = selectedUrl;
                        _selectedImageFile = null;
                        _imageBytes = null;
                      });
                    }
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Color(0xFFFFF3E0),
                    child:
                        Icon(Icons.camera_alt, color: Colors.orange, size: 20),
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
            _imageBytes = bytes;
            _selectedImageFile = null;
            _onlineImageUrl = null;
          });
        } else {
          setState(() {
            _selectedImageFile = File(pickedFile.path);
            _imageBytes = null;
            _onlineImageUrl = null;
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
            _imageBytes = bytes;
            _selectedImageFile = null;
            _onlineImageUrl = null;
          });
        } else {
          setState(() {
            _selectedImageFile = File(pickedFile.path);
            _imageBytes = null;
            _onlineImageUrl = null;
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
    final urlController = TextEditingController(text: _onlineImageUrl ?? '');
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
                    _onlineImageUrl = url;
                    _selectedImageFile = null;
                    _imageBytes = null;
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

  // TextFormField builder helper
  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon, {
    bool required = false,
    bool isNumber = false,
    bool enabled = true,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.black45),
        border: const OutlineInputBorder(),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      validator: (v) {
        if (required && (v == null || v.trim().isEmpty)) {
          return 'Vui lòng nhập $label';
        }
        return null;
      },
    );
  }

  // Category selection row builder
  Widget _buildCategorySelector({required bool enabled}) {
    return InkWell(
      onTap: enabled ? _navigateToCategorySelect : null,
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Nhóm hàng *',
          prefixIcon: Icon(Icons.category, color: Colors.black45),
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                _selectedCategoryPath.isNotEmpty
                    ? _selectedCategoryPath
                    : 'Chọn nhóm hàng *',
                style: TextStyle(
                  color: _selectedCategoryPath.isNotEmpty
                      ? Colors.black87
                      : Colors.black38,
                  fontSize: 15,
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
          orElse: () => const Category(id: '', name: ''),
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

  // Extra Actions Row Builders
  Widget _buildExtraActionRow({
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
        leading: Icon(icon, color: AppColors.primary),
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

  Widget _buildCollapsibleInput(
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    required bool enabled,
  }) {
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
          enabled: enabled,
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

  Widget _buildOtherInfoInputs({required bool enabled}) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.borderLight),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextFormField(
              controller: _noteTemplateController,
              enabled: enabled,
              decoration: const InputDecoration(
                  labelText: 'Mẫu ghi chú', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _componentsController,
              enabled: enabled,
              decoration: const InputDecoration(
                  labelText: 'Hàng thành phần', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
  }

  // Attributes list widget
  Widget _buildAttributesList({required bool enabled}) {
    return Column(
      children: _attributes.map((attr) {
        return Card(
          color: Colors.white,
          margin: const EdgeInsets.only(bottom: 6),
          child: ListTile(
            title: Text('${attr['name']}: ${attr['value']}',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            trailing: enabled
                ? IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 18),
                    onPressed: () {
                      setState(() {
                        _attributes.remove(attr);
                      });
                    },
                  )
                : null,
            dense: true,
          ),
        );
      }).toList(),
    );
  }

  // Attributes Dialog
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
              style:
                  FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Thêm'),
            )
          ],
        );
      },
    );
  }

  // Combo Section Card Builder
  Widget _buildComboSectionCard({required bool enabled}) {
    final allProducts = ref.watch(productListProvider).value ?? [];
    final double suggestedCost = ComboHelper.calculateSuggestedCostPrice(
      components: _comboComponents,
      allProducts: allProducts,
    );

    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: _isCombo ? AppColors.primary : AppColors.borderLight,
          width: _isCombo ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _isCombo,
              onChanged: enabled
                  ? (v) {
                      setState(() {
                        _isCombo = v;
                        if (v && _comboComponents.isNotEmpty) {
                          _costPriceController.text =
                              suggestedCost.toStringAsFixed(0);
                        }
                      });
                    }
                  : null,
              title: const Row(
                children: [
                  Icon(Icons.widgets, color: AppColors.primary, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Sản phẩm Combo / Bộ',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              subtitle: const Text(
                'Tồn kho được tính tự động dựa trên số lượng linh kiện thành phần',
                style: TextStyle(fontSize: 11, color: Colors.black54),
              ),
              activeColor: AppColors.primary,
            ),
            if (_isCombo) ...[
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Danh sách thành phần (${_comboComponents.length})',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (enabled)
                    TextButton.icon(
                      onPressed: _showAddComponentSheet,
                      icon: const Icon(Icons.add_circle_outline, size: 18),
                      label: const Text('Thêm linh kiện'),
                    ),
                ],
              ),
              if (_comboComponents.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: const Column(
                    children: [
                      Icon(Icons.widgets_outlined,
                          color: Colors.black38, size: 32),
                      SizedBox(height: 4),
                      Text(
                        'Chưa có linh kiện nào trong Combo',
                        style:
                            TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                      Text(
                        'Nhấn "Thêm linh kiện" để chọn các sản phẩm thành phần',
                        style:
                            TextStyle(fontSize: 11, color: Colors.black38),
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: _comboComponents.asMap().entries.map((entry) {
                    final index = entry.key;
                    final comp = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  comp.productName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  'Mã: ${comp.productCode}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(
                                    Icons.remove_circle_outline,
                                    size: 20),
                                onPressed: (enabled && comp.quantity > 1)
                                    ? () {
                                        setState(() {
                                          _comboComponents[index] =
                                              comp.copyWith(
                                            quantity: comp.quantity - 1,
                                          );
                                        });
                                      }
                                    : null,
                              ),
                              Text(
                                '${comp.quantity}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline,
                                    size: 20),
                                onPressed: enabled
                                    ? () {
                                        setState(() {
                                          _comboComponents[index] =
                                              comp.copyWith(
                                            quantity: comp.quantity + 1,
                                          );
                                        });
                                      }
                                    : null,
                              ),
                              if (enabled)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: Colors.red, size: 20),
                                  onPressed: () {
                                    setState(() {
                                      _comboComponents.removeAt(index);
                                    });
                                  },
                                ),
                            ],
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              if (_comboComponents.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.lightbulb_outline,
                          color: Colors.amber, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Giá vốn gợi ý: ${NumberFormat('#,###', 'vi_VN').format(suggestedCost)} đ',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      if (enabled)
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _costPriceController.text =
                                  suggestedCost.toStringAsFixed(0);
                            });
                          },
                          child: const Text('Áp dụng',
                              style: TextStyle(fontSize: 12)),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _showAddComponentSheet() {
    final allProducts = ref.read(productListProvider).value ?? [];
    final eligibleProducts = allProducts.where((p) => !p.isCombo).toList();

    String searchQuery = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = eligibleProducts.where((p) {
              final query = searchQuery.toLowerCase();
              return p.name.toLowerCase().contains(query) ||
                  p.code.toLowerCase().contains(query);
            }).toList();

            return DraggableScrollableSheet(
              initialChildSize: 0.7,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Chọn linh kiện thành phần',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        onChanged: (v) => setModalState(() => searchQuery = v),
                        decoration: const InputDecoration(
                          hintText: 'Tìm theo tên hoặc mã hàng...',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const Center(
                                child: Text('Không tìm thấy sản phẩm hợp lệ'),
                              )
                            : ListView.builder(
                                controller: scrollController,
                                itemCount: filtered.length,
                                itemBuilder: (context, index) {
                                  final p = filtered[index];
                                  final isAlreadyAdded = _comboComponents
                                      .any((c) => c.productId == p.id);

                                  return ListTile(
                                    title: Text(p.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    subtitle: Text(
                                        'Mã: ${p.code} | Giá vốn: ${NumberFormat('#,###', 'vi_VN').format(p.costPrice)} đ'),
                                    trailing: isAlreadyAdded
                                        ? const Icon(Icons.check_circle,
                                            color: Colors.green)
                                        : ElevatedButton(
                                            onPressed: () {
                                              setState(() {
                                                _comboComponents.add(
                                                  ComboComponent(
                                                    productId: p.id,
                                                    productCode: p.code,
                                                    productName: p.name,
                                                    quantity: 1,
                                                    costPrice: p.costPrice,
                                                  ),
                                                );
                                              });
                                              setModalState(() {});
                                            },
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor:
                                                  AppColors.primary,
                                              foregroundColor: Colors.white,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 12),
                                            ),
                                            child: const Text('Chọn'),
                                          ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // Save product logic
  void _saveProduct() async {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.read(authProvider);
    if (user != null && !user.canManageProducts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn không có quyền quản lý hàng hóa!'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null && _selectedCategoryPath.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn nhóm hàng!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final storeId = ref.read(currentStoreIdProvider);
      final isEditing = widget.productToUse != null;
      final productId = widget.productToUse?.id ??
          DateTime.now().millisecondsSinceEpoch.toString();
      String? imageUrl = _onlineImageUrl ?? widget.productToUse?.imageUrl;

      // Upload image to Firebase Storage if local image selected
      if (_selectedImageFile != null || _imageBytes != null) {
        final storageRef = FirebaseStorage.instance
            .ref('stores/$storeId/products/$productId.jpg');
        if (kIsWeb && _imageBytes != null) {
          await storageRef.putData(_imageBytes!);
        } else if (_selectedImageFile != null) {
          await storageRef.putFile(_selectedImageFile!);
        }
        imageUrl = await storageRef.getDownloadURL();
      }

      // Read form inputs
      final name = _nameController.text.trim();
      final code = _codeController.text.trim().isNotEmpty
          ? _codeController.text.trim()
          : (name.length > 3
              ? name.substring(0, 3).toUpperCase()
              : name.toUpperCase());

      final price = double.tryParse(_priceController.text.trim()) ?? 0.0;

      double costPrice;
      if (user?.canViewCostPrice == true) {
        costPrice = _costPriceController.text.trim().isNotEmpty
            ? (double.tryParse(_costPriceController.text.trim()) ?? 0.0)
            : (isEditing ? widget.productToUse!.costPrice : price * 0.7);
      } else {
        costPrice =
            isEditing ? widget.productToUse!.costPrice : price * 0.7;
      }

      final stock = int.tryParse(_stockController.text.trim()) ?? 0;
      final minStock = int.tryParse(_minStockController.text.trim());
      final maxStock = int.tryParse(_maxStockController.text.trim());
      final baseUnit = _baseUnitController.text.trim().isNotEmpty
          ? _baseUnitController.text.trim()
          : 'Cái';

      final categoryName = _selectedCategory?.name ??
          (_selectedCategoryPath.isNotEmpty
              ? _selectedCategoryPath.split(' >> ').last
              : 'Khác');

      final note = _noteTemplateController.text.trim();
      final components = _componentsController.text.trim();
      final desc = _descriptionController.text.trim();

      final currentStoreId = ref.read(currentStoreIdProvider);
      final Map<String, int> branchStocks;
      if (isEditing) {
        branchStocks = Map<String, int>.from(widget.productToUse!.branchStocks);
        if (!_isCombo) {
          String targetKey = currentStoreId;
          if (!branchStocks.containsKey(currentStoreId)) {
            if (currentStoreId == 'store_001' && branchStocks.containsKey('branch_1')) {
              targetKey = 'branch_1';
            } else if (currentStoreId == 'store_002' && branchStocks.containsKey('branch_2')) {
              targetKey = 'branch_2';
            }
          }
          branchStocks[targetKey] = stock;
        }
      } else {
        final otherStoreId =
            currentStoreId == 'store_001' ? 'store_002' : 'store_001';
        branchStocks = {
          currentStoreId: stock,
          otherStoreId: 0,
        };
      }

      final product = Product(
        id: productId,
        name: name,
        code: code,
        barcode: _barcodeController.text.trim().isNotEmpty
            ? _barcodeController.text.trim()
            : null,
        brand: _brandController.text.trim().isNotEmpty
            ? _brandController.text.trim()
            : null,
        model: _attributes.isNotEmpty
            ? _attributes.map((a) => '${a['name']}:${a['value']}').join(', ')
            : widget.productToUse?.model,
        price: price,
        costPrice: costPrice,
        branchStocks: branchStocks,
        category: categoryName,
        category3Levels: _selectedCategoryPath.isNotEmpty
            ? _selectedCategoryPath
            : null,
        unit: baseUnit,
        units: _units,
        minStock: minStock,
        maxStock: maxStock,
        description: desc.isNotEmpty ? desc : null,
        noteTemplate: note.isNotEmpty ? note : null,
        components: components.isNotEmpty ? components : null,
        imageUrl: imageUrl,
        isCombo: _isCombo,
        comboComponents: _isCombo ? _comboComponents : const [],
        allowSale: _sellDirectly,
      );

      await ref.read(productRepositoryProvider).upsert(product);
      ref.invalidate(productListProvider);

      if (mounted) {
        Navigator.of(context).pop(product);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(isEditing ? 'Đã cập nhật hàng hóa!' : l10n.productAdded),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi lưu sản phẩm: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
