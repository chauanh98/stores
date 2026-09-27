import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/suppliers/suppliers_providers.dart';
import '../../../application/suppliers/usecases/import_suppliers_usecase.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/excel_helper.dart';
import '../../../core/utils/file_saver.dart';
import '../../../domain/entities/supplier.dart';
import '../widgets/supplier_list_tile.dart';
import 'add_edit_supplier_page.dart';

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => SuppliersPageState();
}

class SuppliersPageState extends ConsumerState<SuppliersPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
    final user = ref.watch(authProvider);
    final kpis = ref.watch(supplierKpisProvider);
    final filterStatus = ref.watch(supplierFilterStatusProvider);
    final suppliersAsync = ref.watch(filteredSuppliersProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          'Nhà Cung Cấp',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: AppColors.white,
        actions: [
          if (kIsWeb && (user?.isAdmin == true))
            PopupMenuButton<String>(
              key: const Key('suppliers_excel_actions_menu'),
              icon: const Icon(Icons.more_vert),
              tooltip: 'Thao tác Excel',
              onSelected: (value) {
                if (value == 'import_excel') {
                  _importSuppliers();
                } else if (value == 'export_excel') {
                  _exportSuppliers();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'import_excel',
                  child: Row(
                    children: [
                      Icon(Icons.upload_file, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text('Nhập từ Excel'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'export_excel',
                  child: Row(
                    children: [
                      Icon(Icons.download, color: AppColors.success),
                      SizedBox(width: 8),
                      Text('Xuất ra Excel'),
                    ],
                  ),
                ),
              ],
            ),
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.primary),
            tooltip: 'Thêm nhà cung cấp',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AddEditSupplierPage(),
                ),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const AddEditSupplierPage(),
            ),
          );
        },
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: AppColors.white),
        label: const Text(
          'Thêm NCC',
          style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.white),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(supplierListNotifierProvider.notifier).refresh(),
        child: Column(
          children: [
            // KPI Summary Header
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: _buildKpiCard(
                      title: 'Tổng NCC',
                      value: '${kpis.totalSuppliers}',
                      color: AppColors.primary,
                      icon: Icons.business,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildKpiCard(
                      title: 'Tổng mua',
                      value: '${currencyFormat.format(kpis.totalPurchase)} đ',
                      color: AppColors.textPrimary,
                      icon: Icons.shopping_bag_outlined,
                      isSmall: true,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _buildKpiCard(
                      title: 'Tổng nợ NCC',
                      value: '${currencyFormat.format(kpis.totalDebt)} đ',
                      color: AppColors.danger,
                      icon: Icons.account_balance_wallet_outlined,
                      isSmall: true,
                    ),
                  ),
                ],
              ),
            ),

            // Search Bar & Filter Chips
            Container(
              color: AppColors.white,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                children: [
                  TextField(
                    controller: _searchController,
                    onChanged: (v) {
                      ref.read(supplierSearchQueryProvider.notifier).state = v;
                    },
                    decoration: InputDecoration(
                      hintText: 'Tìm theo tên, mã NCC, SĐT, địa chỉ...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchController.clear();
                                ref
                                    .read(supplierSearchQueryProvider.notifier)
                                    .state = '';
                              },
                            )
                          : null,
                      filled: true,
                      fillColor: AppColors.surface,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.borderLight),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide:
                            const BorderSide(color: AppColors.borderLight),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildFilterChip(
                        label: 'Tất cả',
                        isSelected: filterStatus == SupplierFilterStatus.all,
                        onTap: () {
                          ref
                              .read(supplierFilterStatusProvider.notifier)
                              .state = SupplierFilterStatus.all;
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        label: 'Còn nợ',
                        isSelected:
                            filterStatus == SupplierFilterStatus.hasDebt,
                        onTap: () {
                          ref
                              .read(supplierFilterStatusProvider.notifier)
                              .state = SupplierFilterStatus.hasDebt;
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        label: 'Hết nợ',
                        isSelected: filterStatus == SupplierFilterStatus.noDebt,
                        onTap: () {
                          ref
                              .read(supplierFilterStatusProvider.notifier)
                              .state = SupplierFilterStatus.noDebt;
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.borderLight),

            // Supplier List
            Expanded(
              child: suppliersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text('Lỗi tải danh sách nhà cung cấp: $err'),
                  ),
                ),
                data: (suppliers) {
                  if (suppliers.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.business_outlined,
                              size: 64,
                              color: AppColors.grey400,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Không tìm thấy nhà cung cấp nào',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Thử tìm kiếm từ khóa khác hoặc thêm mới nhà cung cấp.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const AddEditSupplierPage(),
                                  ),
                                );
                              },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('Thêm Nhà Cung Cấp'),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: suppliers.length,
                    itemBuilder: (context, index) {
                      final supplier = suppliers[index];
                      return SupplierListTile(supplier: supplier);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required Color color,
    required IconData icon,
    bool isSmall = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppColors.textSecondary),
              const SizedBox(width: 4),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: isSmall ? 12 : 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.borderLight,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Future<void> _importSuppliers() async {
    final user = ref.read(authProvider);
    if (!kIsWeb || (user?.isAdmin != true)) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'xls'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không có file nào được chọn')),
          );
        }
        return;
      }

      final fileBytes = result.files.first.bytes ??
          (result.files.first.path != null
              ? await File(result.files.first.path!).readAsBytes()
              : null);

      if (fileBytes == null) {
        throw Exception('Không thể đọc nội dung file');
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final importedSuppliers = ExcelHelper.parseSuppliers(fileBytes);
      final importResult =
          await ref.read(importSuppliersUseCaseProvider).execute(
                suppliers: importedSuppliers,
              );

      ref.invalidate(supplierListNotifierProvider);

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(importResult.toSummaryString()),
            backgroundColor:
                importResult.errors > 0 ? AppColors.warning : AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi nhập file: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  Future<void> _exportSuppliers() async {
    final user = ref.read(authProvider);
    if (!kIsWeb || (user?.isAdmin != true)) return;

    try {
      final suppliersAsync = ref.read(filteredSuppliersProvider);
      final suppliers = suppliersAsync.maybeWhen(
        data: (list) => list,
        orElse: () => <Supplier>[],
      );

      if (suppliers.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Không có dữ liệu để xuất')),
          );
        }
        return;
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      final bytes = await ExcelHelper.exportSuppliers(suppliers);

      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        await saveExcelFile(bytes, 'DanhSachNhaCungCap_Export.xlsx');
      }
    } catch (e) {
      if (mounted) {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Lỗi xuất file: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @visibleForTesting
  Future<void> testImportSuppliers() => _importSuppliers();

  @visibleForTesting
  Future<void> testExportSuppliers() => _exportSuppliers();
}
