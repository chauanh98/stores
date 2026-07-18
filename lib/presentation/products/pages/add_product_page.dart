import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/products/categories_providers.dart';
import '../../../application/products/products_providers.dart';
import '../../../domain/entities/category.dart';
import '../../../domain/entities/product.dart';
import 'select_category_page.dart';

class AddProductPage extends ConsumerStatefulWidget {
  const AddProductPage({super.key});

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

  Category? _selectedCategory;
  String _selectedCategoryPath = '';

  // Image Upload State
  File? _selectedImageFile;
  Uint8List? _imageBytes;
  bool _isLoading = false;

  // Extra Sub-Sections Toggles
  bool _showDescription = false;
  final _descriptionController = TextEditingController();

  bool _showStockLimits = false;
  final _minStockController = TextEditingController();
  final _maxStockController = TextEditingController();

  bool _showOtherInfo = false;
  final _noteTemplateController = TextEditingController();
  final _componentsController = TextEditingController();

  // Attributes & Units states
  final List<Map<String, String>> _attributes = [];
  final List<Map<String, dynamic>> _units = [];
  bool _sellDirectly = true;

  @override
  void dispose() {
    _codeController.dispose();
    _barcodeController.dispose();
    _nameController.dispose();
    _brandController.dispose();
    _costPriceController.dispose();
    _priceController.dispose();
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

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Hàng hóa mới',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        actions: [
          TextButton(
            onPressed: _isLoading ? null : _saveProduct,
            child: const Text(
              'Lưu',
              style: TextStyle(
                  color: Color(0xFF0067AC),
                  fontWeight: FontWeight.bold,
                  fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () {},
          )
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
                    // 1. Image Picker Top Card
                    _buildImagePickerCard(),
                    const SizedBox(height: 16),

                    // 2. Core Fields Card
                    Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            _buildField(_codeController, 'Mã hàng', Icons.tag,
                                trailingIcon: Icons.qr_code_scanner),
                            const SizedBox(height: 16),
                            _buildField(
                                _barcodeController, 'Mã vạch', Icons.qr_code,
                                trailingIcon: Icons.qr_code_scanner),
                            const SizedBox(height: 16),
                            _buildField(
                                _nameController, 'Tên hàng *', Icons.label,
                                required: true),
                            const SizedBox(height: 16),
                            // Category Select
                            _buildCategorySelector(),
                            const SizedBox(height: 16),
                            _buildField(_brandController, 'Thương hiệu',
                                Icons.business),
                            const SizedBox(height: 16),
                            _buildField(
                                _costPriceController, 'Giá vốn', Icons.download,
                                isNumber: true, hint: '0'),
                            const SizedBox(height: 16),
                            _buildField(
                                _priceController, 'Giá bán', Icons.upload,
                                isNumber: true, hint: '0'),
                            const SizedBox(height: 16),
                            _buildField(
                                _stockController, 'Tồn kho', Icons.inventory_2,
                                isNumber: true, hint: '0'),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // 3. Extra Actions
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
                          _descriptionController, 'Nhập mô tả sản phẩm...',
                          maxLines: 3),
                    ],
                    const SizedBox(height: 8),

                    _buildExtraActionRow(
                      icon: Icons.style,
                      label: 'Thêm thuộc tính (Màu sắc, kích thước...)',
                      onTap: _showAttributesDialog,
                      trailingWidget: _attributes.isNotEmpty
                          ? Chip(
                              label: Text('${_attributes.length} thuộc tính'))
                          : null,
                    ),
                    if (_attributes.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _buildAttributesList(),
                    ],
                    const SizedBox(height: 8),

                    _buildExtraActionRow(
                      icon: Icons.straighten,
                      label: 'Thêm đơn vị tính',
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

                    _buildExtraActionRow(
                      icon: Icons.notifications_active_outlined,
                      label: 'Thêm định mức tồn kho',
                      onTap: () =>
                          setState(() => _showStockLimits = !_showStockLimits),
                      isToggled: _showStockLimits,
                    ),
                    if (_showStockLimits) ...[
                      const SizedBox(height: 8),
                      _buildStockLimitsInputs(),
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
                      _buildOtherInfoInputs(),
                    ],
                    const SizedBox(height: 16),

                    // 4. Bottom Switch Direct Sell
                    Card(
                      color: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
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
                        subtitle: const Text(
                            'Cho phép sản phẩm bán trực tiếp tại quầy POS',
                            style: TextStyle(fontSize: 11)),
                        activeColor: const Color(0xFF0067AC),
                      ),
                    ),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
    );
  }

  // Widget Image Picker Card
  Widget _buildImagePickerCard() {
    return GestureDetector(
      onTap: _showImageSourceSheet,
      child: Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: Container(
          height: 140,
          width: double.infinity,
          alignment: Alignment.center,
          child: _selectedImageFile != null || _imageBytes != null
              ? Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _imageBytes != null
                            ? Image.memory(_imageBytes!, fit: BoxFit.cover)
                            : Image.file(_selectedImageFile!,
                                fit: BoxFit.cover),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        onTap: () => setState(() {
                          _selectedImageFile = null;
                          _imageBytes = null;
                        }),
                        child: CircleAvatar(
                          radius: 14,
                          backgroundColor: Colors.black.withOpacity(0.5),
                          child: const Icon(Icons.close,
                              color: Colors.white, size: 16),
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
                        color: const Color(0xFF0067AC).withOpacity(0.06),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.camera_alt,
                          color: Color(0xFF0067AC), size: 28),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tải ảnh sản phẩm',
                      style: TextStyle(
                          fontSize: 13,
                          color: Colors.black54,
                          fontWeight: FontWeight.bold),
                    )
                  ],
                ),
        ),
      ),
    );
  }

  // Display Image Source Sheet
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.image, color: Color(0xFF0067AC)),
                title: const Text('Chọn ảnh trên máy'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImageFromFile();
                },
              ),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Colors.orange),
                title: const Text('Chụp ảnh mới'),
                onTap: () {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content:
                            Text('Tính năng máy ảnh đang được khởi động...')),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  // Pick Image from file_picker
  void _pickImageFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (kIsWeb) {
          setState(() {
            _imageBytes = file.bytes;
          });
        } else {
          setState(() {
            _selectedImageFile = File(file.path!);
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Lỗi chọn ảnh: $e')),
      );
    }
  }

  // TextFormField builder helper
  Widget _buildField(
      TextEditingController controller, String label, IconData icon,
      {bool required = false,
      bool isNumber = false,
      IconData? trailingIcon,
      String? hint}) {
    return TextFormField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.black45),
        suffixIcon: trailingIcon != null
            ? IconButton(
                icon: Icon(trailingIcon, color: const Color(0xFF0067AC)),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Đang khởi động camera quét mã...')),
                  );
                },
              )
            : null,
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
  Widget _buildCategorySelector() {
    return InkWell(
      onTap: _navigateToCategorySelect,
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
                    : 'Chọn nhóm hàng',
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
      // Build full path recursively
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
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF0067AC)),
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

  Widget _buildCollapsibleInput(TextEditingController controller, String hint,
      {int maxLines = 1}) {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
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
        side: const BorderSide(color: Color(0xFFE2E8F0)),
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

  Widget _buildOtherInfoInputs() {
    return Card(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            TextFormField(
              controller: _noteTemplateController,
              decoration: const InputDecoration(
                  labelText: 'Mẫu ghi chú', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _componentsController,
              decoration: const InputDecoration(
                  labelText: 'Hàng thành phần', border: OutlineInputBorder()),
            ),
          ],
        ),
      ),
    );
  }

  // Attributes list widget
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
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0067AC)),
              child: const Text('Thêm'),
            )
          ],
        );
      },
    );
  }

  // Units list widget
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

  // Units Dialog
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
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0067AC)),
              child: const Text('Thêm'),
            )
          ],
        );
      },
    );
  }

  // Save product logic
  void _saveProduct() async {
    final l10n = AppLocalizations.of(context)!;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategory == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng chọn nhóm hàng!')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final storeId = ref.read(currentStoreIdProvider);
      final productId = DateTime.now().millisecondsSinceEpoch.toString();
      String? imageUrl;

      // Upload image to Firebase Storage if selected
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
      final costPrice = _costPriceController.text.trim().isNotEmpty
          ? (double.tryParse(_costPriceController.text.trim()) ?? 0.0)
          : price * 0.7;

      final stock = int.tryParse(_stockController.text.trim()) ?? 0;

      // Attributes maps conversion
      final note = _noteTemplateController.text.trim();
      final components = _componentsController.text.trim();
      final desc = _descriptionController.text.trim();

      final product = Product(
        id: productId,
        name: name,
        code: code,
        barcode: _barcodeController.text.trim(),
        brand: _brandController.text.trim(),
        model: _attributes.map((a) => '${a['name']}:${a['value']}').join(', '),
        price: price,
        costPrice: costPrice,
        branchStocks: {'branch_1': stock, 'branch_2': 0},
        category: _selectedCategory!.name,
        category3Levels: _selectedCategoryPath,
        unit: _units.isNotEmpty ? _units.first['name'] : 'Cái',
        description: desc.isNotEmpty ? desc : null,
        noteTemplate: note.isNotEmpty ? note : null,
        components: components.isNotEmpty ? components : null,
        imageUrl: imageUrl,
      );

      await ref.read(productRepositoryProvider).upsert(product);
      ref.invalidate(productListProvider);

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(l10n.productAdded), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Lỗi thêm sản phẩm: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }
}
