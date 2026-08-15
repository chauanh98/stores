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

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);

    if (user?.isSupervisor != true) {
      return Scaffold(
        appBar: AppBar(title: const Text('Cấu hình Hóa đơn & Nhận tiền')),
        body: const Center(
          child: Text(
            'Chỉ tài khoản Giám sát / Chủ chuỗi (Supervisor) mới có quyền truy cập trang này.',
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
      amount: 100000,
      addInfo: 'HD000001',
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Cấu hình Hóa đơn & VietQR',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
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
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _storeNameController,
                decoration: const InputDecoration(
                  labelText: 'Tên cửa hàng (Header)',
                  border: OutlineInputBorder(),
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
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneController,
                decoration: const InputDecoration(
                  labelText: 'Số điện thoại hotline',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 24),

              // 2. THÔNG TIN NGÂN HÀNG & VIETQR
              const Text(
                'THÔNG TIN TÀI KHOẢN NGÂN HÀNG (VIETQR)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
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
                ),
                validator: (v) => v == null || v.trim().isEmpty
                    ? 'Vui lòng nhập tên chủ tài khoản'
                    : null,
                onChanged: (_) => setState(() {}),
              ),

              const SizedBox(height: 24),

              // 3. CAM KẾT & CHÂN TRANG HÓA ĐƠN
              const Text(
                'GHI CHÚ CHÂN HÓA ĐƠN (FOOTER)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: AppColors.primary,
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

              // 4. LIVE PREVIEW VIETQR
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.primary.withOpacity(0.2)),
                ),
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Image.network(
                      vietQrUrl,
                      width: 90,
                      height: 90,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.qr_code_2,
                        size: 80,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Xem trước mã VietQR:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Ngân hàng: ${VietQRHelper.supportedBanks[_selectedBankId] ?? _selectedBankId}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          Text(
                            'STK: ${_accountNoController.text}',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Tên: ${_accountNameController.text.toUpperCase()}',
                            style: const TextStyle(fontSize: 11),
                          ),
                        ],
                      ),
                    )
                  ],
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
                      ? const CircularProgressIndicator(color: Colors.white)
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
      );

      final ds = ref.read(storePaymentConfigDataSourceProvider);
      await ds.saveConfig(updatedConfig);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã cập nhật thông tin nhận tiền & hóa đơn thành công!'),
            backgroundColor: Colors.green,
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
