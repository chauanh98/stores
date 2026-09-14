import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/suppliers/suppliers_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/code_generator_helper.dart';
import '../../../core/utils/currency_input_formatter.dart';
import '../../../domain/entities/supplier.dart';
import '../../../domain/entities/supplier_debt_transaction.dart';

class AddEditSupplierPage extends ConsumerStatefulWidget {
  final Supplier? supplier;

  const AddEditSupplierPage({super.key, this.supplier});

  @override
  ConsumerState<AddEditSupplierPage> createState() => _AddEditSupplierPageState();
}

class _AddEditSupplierPageState extends ConsumerState<AddEditSupplierPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _codeController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _addressController;
  late final TextEditingController _taxCodeController;
  late final TextEditingController _totalPurchaseController;
  late final TextEditingController _currentDebtController;
  late final TextEditingController _noteController;
  bool _isLoading = false;

  bool get _isEditing => widget.supplier != null;

  @override
  void initState() {
    super.initState();
    final s = widget.supplier;
    _nameController = TextEditingController(text: s?.name ?? '');
    _codeController = TextEditingController(text: s?.code ?? '');
    _phoneController = TextEditingController(text: s?.phone ?? '');
    _emailController = TextEditingController(text: s?.email ?? '');
    _addressController = TextEditingController(text: s?.address ?? '');
    _taxCodeController = TextEditingController(text: s?.taxCode ?? '');
    _totalPurchaseController = TextEditingController(
      text: s != null && s.totalPurchase > 0
          ? NumberFormat('#,###', 'vi_VN').format(s.totalPurchase)
          : '',
    );
    _currentDebtController = TextEditingController(
      text: s != null && s.currentDebt > 0
          ? NumberFormat('#,###', 'vi_VN').format(s.currentDebt)
          : '',
    );
    _noteController = TextEditingController(text: s?.note ?? '');

    // Auto-generate code if creating new supplier
    if (!_isEditing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoGenerateCode();
      });
    }
  }

  void _autoGenerateCode() {
    if (_codeController.text.isNotEmpty) return;
    final suppliers = ref.read(supplierListNotifierProvider).value ?? [];
    final existingCodes = suppliers.map((s) => s.code).toList();
    final nextCode = CodeGeneratorHelper.generateNextSupplierCode(existingCodes);
    setState(() {
      _codeController.text = nextCode;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _taxCodeController.dispose();
    _totalPurchaseController.dispose();
    _currentDebtController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  double _parseAmount(String text) {
    final clean = text.replaceAll(RegExp(r'[^0-9]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final user = ref.read(authProvider);
      final createdBy = widget.supplier?.createdBy ?? user?.username ?? 'Admin';
      final id = widget.supplier?.id ??
          (_codeController.text.trim().isNotEmpty
              ? _codeController.text.trim().toUpperCase()
              : 'NCC_${DateTime.now().millisecondsSinceEpoch}');
      final code = _codeController.text.trim().isNotEmpty
          ? _codeController.text.trim().toUpperCase()
          : id;

      final totalPurchase = _parseAmount(_totalPurchaseController.text);
      final currentDebt = _parseAmount(_currentDebtController.text);

      final newSupplier = Supplier(
        id: id,
        code: code,
        name: _nameController.text.trim(),
        phone: _phoneController.text.trim(),
        email: _emailController.text.trim(),
        address: _addressController.text.trim(),
        taxCode: _taxCodeController.text.trim().isNotEmpty
            ? _taxCodeController.text.trim()
            : null,
        totalPurchase: totalPurchase,
        currentDebt: currentDebt,
        note: _noteController.text.trim().isNotEmpty
            ? _noteController.text.trim()
            : null,
        status: widget.supplier?.status ?? 'active',
        branch: widget.supplier?.branch,
        createdAt: widget.supplier?.createdAt ?? DateTime.now().toIso8601String(),
        createdBy: createdBy,
      );

      await ref
          .read(supplierListNotifierProvider.notifier)
          .upsertSupplier(newSupplier);

      // If creating new supplier with initial debt, record initial transaction
      if (!_isEditing && currentDebt > 0) {
        final repo = ref.read(supplierRepositoryProvider);
        await repo.recordDebtTransaction(
          SupplierDebtTransaction(
            id: 'TX_INIT_${DateTime.now().millisecondsSinceEpoch}',
            supplierId: id,
            date: DateTime.now(),
            type: SupplierDebtType.importBill,
            amount: currentDebt,
            remainingDebt: currentDebt,
            referenceCode: 'INIT_$code',
            note: 'Dư nợ đầu kỳ khi tạo nhà cung cấp',
            createdBy: createdBy,
          ),
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop(newSupplier);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isEditing
                ? 'Đã cập nhật nhà cung cấp "${newSupplier.name}"'
                : 'Đã thêm nhà cung cấp "${newSupplier.name}" thành công',
          ),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lỗi: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Chỉnh Sửa Nhà Cung Cấp' : 'Thêm Nhà Cung Cấp Mới',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: TextButton.icon(
              onPressed: _isLoading ? null : _save,
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check, color: AppColors.primary),
              label: Text(
                _isEditing ? 'Lưu' : 'Tạo mới',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Basic Info Card
            _buildSectionCard(
              title: 'THÔNG TIN CHUNG',
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Tên nhà cung cấp *',
                    hintText: 'VD: Công ty TNHH ABC',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Vui lòng nhập tên nhà cung cấp'
                      : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _codeController,
                        decoration: const InputDecoration(
                          labelText: 'Mã nhà cung cấp *',
                          hintText: 'VD: NCC000001',
                          prefixIcon: Icon(Icons.tag),
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Vui lòng nhập mã NCC'
                            : null,
                      ),
                    ),
                    if (!_isEditing) ...[
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _autoGenerateCode,
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Sinh mã tự động',
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại',
                    hintText: 'VD: 0912345678',
                    prefixIcon: Icon(Icons.phone),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    hintText: 'VD: contact@ncc.com',
                    prefixIcon: Icon(Icons.email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _addressController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Địa chỉ',
                    hintText: 'Số nhà, tên đường, phường/xã, quận/huyện...',
                    prefixIcon: Icon(Icons.location_on),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _taxCodeController,
                  decoration: const InputDecoration(
                    labelText: 'Mã số thuế',
                    hintText: 'VD: 0302861742',
                    prefixIcon: Icon(Icons.badge),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Debt & Finance Card
            _buildSectionCard(
              title: 'CÔNG NỢ & MUA HÀNG BAN ĐẦU',
              children: [
                TextFormField(
                  controller: _totalPurchaseController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CurrencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Tổng tiền mua hàng (VNĐ)',
                    hintText: '0',
                    prefixIcon: Icon(Icons.shopping_cart),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _currentDebtController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [CurrencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Nợ cần trả hiện tại (VNĐ)',
                    hintText: '0',
                    prefixIcon: Icon(Icons.account_balance_wallet),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Notes Card
            _buildSectionCard(
              title: 'GHI CHÚ THÊM',
              children: [
                TextFormField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Ghi chú',
                    hintText: 'Thông tin bổ sung về nhà cung cấp...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Submit Button
            FilledButton.icon(
              onPressed: _isLoading ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: _isLoading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(
                _isEditing ? 'CẬP NHẬT NHÀ CUNG CẤP' : 'TẠO MỚI NHÀ CUNG CẤP',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
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
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: Colors.black54,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}
