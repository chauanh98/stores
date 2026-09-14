import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/suppliers/suppliers_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../../../domain/entities/supplier.dart';
import '../../../domain/entities/supplier_debt_transaction.dart';
import '../widgets/supplier_debt_adjustment_dialog.dart';
import '../widgets/supplier_debt_payment_dialog.dart';
import 'add_edit_supplier_page.dart';

class SupplierDetailPage extends ConsumerStatefulWidget {
  final Supplier supplier;

  const SupplierDetailPage({super.key, required this.supplier});

  @override
  ConsumerState<SupplierDetailPage> createState() => _SupplierDetailPageState();
}

class _SupplierDetailPageState extends ConsumerState<SupplierDetailPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Supplier _getLiveSupplier() {
    final suppliers = ref.watch(supplierListNotifierProvider).value;
    if (suppliers != null) {
      final found = suppliers.where((s) => s.id == widget.supplier.id);
      if (found.isNotEmpty) return found.first;
    }
    return widget.supplier;
  }

  Future<void> _confirmDelete(Supplier current) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa nhà cung cấp'),
        content: Text(
          'Bạn có chắc chắn muốn xóa nhà cung cấp "${current.name}"? Thao tác này không thể hoàn tác.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await ref
          .read(supplierListNotifierProvider.notifier)
          .deleteSupplier(current.id);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Đã xóa nhà cung cấp "${current.name}"'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  void _copyToClipboard(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Đã sao chép $label: $text'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final current = _getLiveSupplier();
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final debtTxsAsync = ref.watch(supplierDebtTransactionsProvider(current.id));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          current.name,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.edit, color: AppColors.primary),
            tooltip: 'Chỉnh sửa',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AddEditSupplierPage(supplier: current),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
            tooltip: 'Xóa nhà cung cấp',
            onPressed: () => _confirmDelete(current),
          ),
        ],
      ),
      body: Column(
        children: [
          // Top Summary Header Card
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      child: Text(
                        current.name.isNotEmpty
                            ? current.name[0].toUpperCase()
                            : 'N',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            current.name,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceLight,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                      color: AppColors.borderLight),
                                ),
                                child: Text(
                                  current.code,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              if (current.taxCode != null &&
                                  current.taxCode!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Text(
                                  'MST: ${current.taxCode}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (current.phone.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0),
                              child: InkWell(
                                onTap: () => _copyToClipboard(
                                    current.phone, 'số điện thoại'),
                                child: Row(
                                  children: [
                                    const Icon(Icons.phone,
                                        size: 13, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      current.phone,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(Icons.copy,
                                        size: 11, color: Colors.grey),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // KPI Overview Numbers
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.borderLight),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Tổng mua hàng',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${currencyFormat.format(current.totalPurchase)} đ',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: current.currentDebt > 0
                              ? AppColors.dangerLight.withOpacity(0.5)
                              : AppColors.successLight.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: current.currentDebt > 0
                                ? AppColors.danger.withOpacity(0.3)
                                : AppColors.success.withOpacity(0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nợ cần trả NCC',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${currencyFormat.format(current.currentDebt)} đ',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: current.currentDebt > 0
                                    ? AppColors.danger
                                    : AppColors.success,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Action Buttons Bar
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (_) =>
                                SupplierDebtPaymentDialog(supplier: current),
                          );
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.payment, size: 18),
                        label: const Text('Trả nợ NCC'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        showDialog(
                          context: context,
                          builder: (_) =>
                              SupplierDebtAdjustmentDialog(supplier: current),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.warning,
                        side: const BorderSide(color: AppColors.warning),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      icon: const Icon(Icons.tune, size: 18),
                      label: const Text('Điều chỉnh nợ'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Tab Bar
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textSecondary,
              indicatorColor: AppColors.primary,
              indicatorWeight: 3,
              tabs: const [
                Tab(text: 'LỊCH SỬ CÔNG NỢ'),
                Tab(text: 'THÔNG TIN CHI TIẾT'),
              ],
            ),
          ),
          const Divider(height: 1, color: AppColors.borderLight),

          // Tab Views
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Lịch sử công nợ
                debtTxsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (err, _) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Text('Lỗi tải lịch sử công nợ: $err'),
                    ),
                  ),
                  data: (transactions) {
                    if (transactions.isEmpty) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.history,
                                size: 48, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'Chưa có lịch sử giao dịch công nợ',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: transactions.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final tx = transactions[index];
                        return _buildDebtTxCard(tx, currencyFormat);
                      },
                    );
                  },
                ),

                // Tab 2: Thông tin chi tiết
                ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _buildDetailItem(
                        'Mã nhà cung cấp', current.code, Icons.tag),
                    _buildDetailItem(
                        'Tên nhà cung cấp', current.name, Icons.business),
                    _buildDetailItem('Số điện thoại',
                        current.phone.isNotEmpty ? current.phone : 'Chưa có',
                        Icons.phone),
                    _buildDetailItem('Email',
                        current.email.isNotEmpty ? current.email : 'Chưa có',
                        Icons.email),
                    _buildDetailItem('Địa chỉ',
                        current.address.isNotEmpty ? current.address : 'Chưa có',
                        Icons.location_on),
                    _buildDetailItem('Mã số thuế',
                        current.taxCode ?? 'Chưa có', Icons.badge),
                    _buildDetailItem(
                        'Chi nhánh', current.branch ?? 'Tất cả chi nhánh',
                        Icons.store),
                    _buildDetailItem('Ghi chú',
                        current.note ?? 'Không có', Icons.notes),
                    _buildDetailItem('Người tạo',
                        current.createdBy ?? 'Admin', Icons.person),
                    if (current.createdAt != null)
                      _buildDetailItem('Ngày tạo', current.createdAt!,
                          Icons.calendar_today),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDebtTxCard(
      SupplierDebtTransaction tx, NumberFormat currencyFormat) {
    final isIncrease = tx.amount > 0;
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    Color badgeColor;
    Color badgeTextColor;
    IconData icon;

    switch (tx.type) {
      case SupplierDebtType.importBill:
        badgeColor = AppColors.dangerLight;
        badgeTextColor = AppColors.danger;
        icon = Icons.call_received;
        break;
      case SupplierDebtType.payment:
        badgeColor = AppColors.successLight;
        badgeTextColor = AppColors.success;
        icon = Icons.payment;
        break;
      case SupplierDebtType.adjustment:
        badgeColor = AppColors.warningLight;
        badgeTextColor = AppColors.warning;
        icon = Icons.tune;
        break;
      case SupplierDebtType.returnOrder:
        badgeColor = AppColors.supervisorLight;
        badgeTextColor = AppColors.supervisor;
        icon = Icons.replay;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 14, color: badgeTextColor),
                    const SizedBox(width: 4),
                    Text(
                      tx.type.displayName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: badgeTextColor,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Text(
                '${isIncrease ? '+' : ''}${currencyFormat.format(tx.amount)} đ',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isIncrease ? AppColors.danger : AppColors.success,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                dateFormat.format(tx.date),
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              Text(
                'Dư nợ sau GD: ${currencyFormat.format(tx.remainingDebt)} đ',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          if (tx.referenceCode != null && tx.referenceCode!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                'Chứng từ: ${tx.referenceCode}',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          if (tx.note != null && tx.note!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4.0),
              child: Text(
                'Ghi chú: ${tx.note}',
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.black54,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(String label, String value, IconData icon) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
