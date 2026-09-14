import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../application/suppliers/suppliers_providers.dart';
import '../../../core/theme/app_colors.dart';
import '../widgets/supplier_list_tile.dart';
import 'add_edit_supplier_page.dart';

class SuppliersPage extends ConsumerStatefulWidget {
  const SuppliersPage({super.key});

  @override
  ConsumerState<SuppliersPage> createState() => _SuppliersPageState();
}

class _SuppliersPageState extends ConsumerState<SuppliersPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormat = NumberFormat('#,###', 'vi_VN');
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
        backgroundColor: Colors.white,
        actions: [
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
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text(
          'Thêm NCC',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(supplierListNotifierProvider.notifier).refresh(),
        child: Column(
          children: [
            // KPI Summary Header
            Container(
              color: Colors.white,
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
                      color: Colors.black87,
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
              color: Colors.white,
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
                          ref.read(supplierFilterStatusProvider.notifier).state =
                              SupplierFilterStatus.all;
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        label: 'Còn nợ',
                        isSelected:
                            filterStatus == SupplierFilterStatus.hasDebt,
                        onTap: () {
                          ref.read(supplierFilterStatusProvider.notifier).state =
                              SupplierFilterStatus.hasDebt;
                        },
                      ),
                      const SizedBox(width: 8),
                      _buildFilterChip(
                        label: 'Hết nợ',
                        isSelected: filterStatus == SupplierFilterStatus.noDebt,
                        onTap: () {
                          ref.read(supplierFilterStatusProvider.notifier).state =
                              SupplierFilterStatus.noDebt;
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
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
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
                            Icon(
                              Icons.business_outlined,
                              size: 64,
                              color: Colors.grey.shade400,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Không tìm thấy nhà cung cấp nào',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.black87,
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
            color: isSelected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }
}
