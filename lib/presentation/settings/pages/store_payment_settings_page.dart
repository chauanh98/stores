import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/settings/store_payment_config_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/vietqr_helper.dart';
import '../../../domain/entities/store_payment_config.dart';

class StorePaymentSettingsPage extends ConsumerStatefulWidget {
  const StorePaymentSettingsPage({super.key});

  @override
  ConsumerState<StorePaymentSettingsPage> createState() =>
      _StorePaymentSettingsPageState();
}

class _StorePaymentSettingsPageState
    extends ConsumerState<StorePaymentSettingsPage> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _storeNameController;
  late TextEditingController _addressController;
  late TextEditingController _phoneController;
  late TextEditingController _accountNoController;
  late TextEditingController _accountNameController;
  late TextEditingController _footerNoteController;

  String _selectedBankId = 'vietinbank';
  String _selectedPaperSize = 'k80';
  bool _showVietQR = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final config = ref.read(storePaymentConfigProvider);

    _storeNameController = TextEditingController(text: config.storeName);
    _addressController = TextEditingController(text: config.address);
    _phoneController = TextEditingController(text: config.phone);
    _accountNoController = TextEditingController(text: config.accountNo);
    _accountNameController = TextEditingController(text: config.accountName);
    _footerNoteController = TextEditingController(text: config.footerNote);
    _selectedBankId = config.bankId;
    _selectedPaperSize = config.paperSize;
    _showVietQR = config.showVietQR;
  }

  @override
  void dispose() {
    _storeNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _accountNoController.dispose();
    _accountNameController.dispose();
    _footerNoteController.dispose();
    super.dispose();
  }

  String _getPaperSizeLabel(String size) {
    switch (size.toLowerCase()) {
      case 'k58':
        return 'K58 (58mm)';
      case 'a4':
        return 'A4 (Chuẩn)';
      case 'k80':
      default:
        return 'K80 (80mm)';
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);

    if (user?.canManagePaymentConfig != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cấu hình Hóa đơn & Nhận tiền')),
        body: const Center(
          child: Text(
            'Chỉ tài khoản Quản trị / Giám sát (Admin / Supervisor) mới có quyền truy cập trang này.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.danger, fontSize: 14),
          ),
        ),
      );
    }

    final vietQrUrl = VietQRHelper.buildVietQRImageUrl(
      bankId: _selectedBankId,
      accountNo: _accountNoController.text,
      accountName: _accountNameController.text,
      amount: 70000,
      addInfo: 'HD000001',
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Cấu hình Hóa đơn & VietQR',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. THÔNG TIN CỬA HÀNG
              const Text(
                'THÔNG TIN CỬA HÀNG TRÊN HÓA ĐƠN',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _storeNameController,
                decoration: const InputDecoration(
                  labelText: 'Tên cửa hàng (Header)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.storefront_outlined),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Vui lòng nhập tên cửa hàng'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Địa chỉ cửa hàng',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.location_on_outlined),
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại hotline',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 24),

              // 2. CẤU HÌNH KHỔ GIẤY & IN VIETQR
              const Text(
                'CẤU HÌNH MẪU IN & KHỔ GIẤY',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                elevation: 0,
                color: AppColors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: const BorderSide(color: AppColors.grey300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Khổ giấy in hóa đơn:',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('K80 (80mm)'),
                            selected: _selectedPaperSize == 'k80',
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedPaperSize = 'k80');
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('K58 (58mm)'),
                            selected: _selectedPaperSize == 'k58',
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedPaperSize = 'k58');
                              }
                            },
                          ),
                          ChoiceChip(
                            label: const Text('A4 (Chuẩn)'),
                            selected: _selectedPaperSize == 'a4',
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedPaperSize = 'a4');
                              }
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'In mã VietQR trên hóa đơn',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        subtitle: const Text(
                          'Tự động tạo mã QR thanh toán ngân hàng trên mỗi phiếu in',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.textSecondary),
                        ),
                        value: _showVietQR,
                        activeColor: AppColors.primary,
                        onChanged: (val) {
                          setState(() => _showVietQR = val);
                        },
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // 3. THÔNG TIN NGÂN HÀNG & VIETQR
              const Text(
                'THÔNG TIN TÀI KHOẢN NGÂN HÀNG (VIETQR)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: VietQRHelper.supportedBanks.containsKey(_selectedBankId)
                    ? _selectedBankId
                    : 'vietinbank',
                decoration: const InputDecoration(
                  labelText: 'Ngân hàng nhận tiền',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.account_balance_outlined),
                ),
                items: VietQRHelper.supportedBanks.entries.map((e) {
                  return DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  );
                }).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _selectedBankId = v;
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNoController,
                decoration: const InputDecoration(
                  labelText: 'Số tài khoản ngân hàng',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.credit_card_outlined),
                ),
                keyboardType: TextInputType.number,
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Vui lòng nhập số tài khoản'
                    : null,
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _accountNameController,
                decoration: const InputDecoration(
                  labelText: 'Tên chủ tài khoản (Viết hoa)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person_outline),
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Vui lòng nhập tên chủ tài khoản'
                    : null,
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 24),

              // 4. CAM KẾT & CHÂN TRANG HÓA ĐƠN
              const Text(
                'GHI CHÚ CHÂN HÓA ĐƠN (FOOTER)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _footerNoteController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Dòng cam kết / Lời cảm ơn',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 24),

              // 5. XEM TRƯỚC HÓA ĐƠN IN THỰC TẾ (LIVE RECEIPT PREVIEW)
              const Text(
                'XEM TRƯỚC HÓA ĐƠN IN THỰC TẾ (LIVE PREVIEW)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              Center(
                child: Container(
                  width: _selectedPaperSize == 'k58'
                      ? 280
                      : _selectedPaperSize == 'a4'
                          ? 360
                          : 320,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.grey300),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.black.withOpacity(0.06),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Badge Khổ Giấy
                      Align(
                        alignment: Alignment.topRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _getPaperSizeLabel(_selectedPaperSize),
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),

                      // Tên Cửa Hàng
                      Text(
                        _storeNameController.text.trim().isNotEmpty
                            ? _storeNameController.text.trim()
                            : 'TÊN CỬA HÀNG',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _addressController.text.trim().isNotEmpty
                            ? _addressController.text.trim()
                            : 'Địa chỉ cửa hàng',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        'Hotline: ${_phoneController.text.trim().isNotEmpty ? _phoneController.text.trim() : '09xx.xxx.xxx'}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 1, thickness: 1),
                      const SizedBox(height: 8),

                      // Tiêu đề hóa đơn
                      const Text(
                        'HÓA ĐƠN BÁN HÀNG',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const Text(
                        'Mã HĐ: HD000001 • 19/08/2026 10:30',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 10, color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Khách hàng: Khách lẻ',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),

                      // Danh sách món mẫu
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              flex: 5,
                              child: Text('Tên món',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11))),
                          Expanded(
                              flex: 2,
                              child: Text('SL',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11))),
                          Expanded(
                              flex: 3,
                              child: Text('T.Tiền',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11))),
                        ],
                      ),
                      const Divider(height: 8),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              flex: 5,
                              child: Text('Cà phê sữa đá',
                                  style: TextStyle(fontSize: 11))),
                          Expanded(
                              flex: 2,
                              child: Text('2',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11))),
                          Expanded(
                              flex: 3,
                              child: Text('50.000 đ',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 11))),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                              flex: 5,
                              child: Text('Bánh mì pate trứng',
                                  style: TextStyle(fontSize: 11))),
                          Expanded(
                              flex: 2,
                              child: Text('1',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 11))),
                          Expanded(
                              flex: 3,
                              child: Text('30.000 đ',
                                  textAlign: TextAlign.right,
                                  style: TextStyle(fontSize: 11))),
                        ],
                      ),
                      const Divider(height: 12),

                      // Tổng tiền
                      _buildPreviewSummaryRow('Tổng tiền hàng:', '80.000 đ'),
                      const SizedBox(height: 2),
                      _buildPreviewSummaryRow('Giảm giá:', '-10.000 đ'),
                      const SizedBox(height: 2),
                      _buildPreviewSummaryRow(
                        'Khách phải trả:',
                        '70.000 đ',
                        isBold: true,
                        fontSize: 12,
                        valueColor: AppColors.primary,
                      ),
                      const SizedBox(height: 2),
                      _buildPreviewSummaryRow('Đã thanh toán:', '70.000 đ'),

                      // Khối VietQR nếu bật
                      if (_showVietQR) ...[
                        const Divider(height: 16),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.15)),
                          ),
                          child: Column(
                            children: [
                              Image.network(
                                vietQrUrl,
                                width: 85,
                                height: 85,
                                errorBuilder: (_, __, ___) => const Icon(
                                  Icons.qr_code_2,
                                  size: 75,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              const Text(
                                'Quét mã VietQR để thanh toán',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.primary,
                                ),
                              ),
                              Text(
                                '${VietQRHelper.supportedBanks[_selectedBankId] ?? _selectedBankId} - ${_accountNoController.text}',
                                style: const TextStyle(
                                    fontSize: 9, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 6),
                      Text(
                        _footerNoteController.text.trim().isNotEmpty
                            ? _footerNoteController.text.trim()
                            : 'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 32),

              // NÚT LƯU CẤU HÌNH
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _isSaving ? null : _saveConfig,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: AppColors.white)
                      : const Text(
                          'Lưu Cấu Hình Hóa Đơn',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
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

  Widget _buildPreviewSummaryRow(
    String label,
    String value, {
    bool isBold = false,
    Color? valueColor,
    double fontSize = 11,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: fontSize,
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: valueColor,
          ),
        ),
      ],
    );
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final storeId = ref.read(currentStoreIdProvider);
      final bankName =
          VietQRHelper.supportedBanks[_selectedBankId] ?? _selectedBankId;

      final updatedConfig = StorePaymentConfig(
        storeId: storeId,
        storeName: _storeNameController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        bankId: _selectedBankId,
        bankName: bankName,
        accountNo: _accountNoController.text.trim(),
        accountName: _accountNameController.text.trim().toUpperCase(),
        footerNote: _footerNoteController.text.trim(),
        paperSize: _selectedPaperSize,
        showVietQR: _showVietQR,
      );

      final ds = ref.read(storePaymentConfigDataSourceProvider);
      await ds.saveConfig(updatedConfig);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Đã cập nhật thông tin nhận tiền & hóa đơn thành công!'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi khi lưu cấu hình: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
