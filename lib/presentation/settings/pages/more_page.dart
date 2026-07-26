import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../customers/pages/customers_page.dart';
import 'account_management_page.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider);
    final currentStore = ref.watch(currentStoreIdProvider);
    final storeNamesAsync = ref.watch(availableStoresProvider);
    final selectedBranchIds = ref.watch(selectedBranchesProvider);

    // Tên chi nhánh hiện tại
    String branchName = 'Tất cả chi nhánh';
    if (selectedBranchIds.length == 1) {
      final mockBranches = getMockBranches(currentStore);
      branchName =
          mockBranches.firstWhere((b) => b.id == selectedBranchIds.first).name;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.moreOptions,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
      ),
      body: ListView(
        children: [
          // 1. Header thông tin cửa hàng & tài khoản
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.primary,
                  child: Text(
                    (user?.username ?? 'K').substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ref.watch(currentStoreNameProvider).when(
                            data: (name) => Text(
                              name,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: Colors.black87),
                            ),
                            loading: () => const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2)),
                            error: (_, __) => Text('${l10n.importError}'),
                          ),
                      const SizedBox(height: 4),
                      Text(
                        'Tài khoản: ${user?.username ?? 'Nhân viên'}',
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Chi nhánh: $branchName',
                        style: const TextStyle(
                            color: AppColors.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      )
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.black38)
              ],
            ),
          ),
          const SizedBox(height: 12),

          // 2. Nhóm chức năng: Giao dịch
          _buildMenuSection(
            context,
            'GIAO DỊCH',
            [
              _MenuItem(
                  Icons.storefront_outlined, 'Bán hàng', AppColors.primary, () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Hãy dùng Tab Bán hàng ở thanh điều hướng dưới!')));
              }),
              _MenuItem(
                  Icons.receipt_long_outlined, 'Hoá đơn', AppColors.warning,
                  () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('Hãy dùng Tab Hoá đơn ở thanh điều hướng dưới!')));
              }),
              _MenuItem(Icons.assignment_outlined, 'Đặt hàng', Colors.teal,
                  () => _showMockMessage(context, 'Đặt hàng')),
              _MenuItem(
                  Icons.assignment_return_outlined,
                  'Trả hàng',
                  AppColors.danger,
                  () => _showMockMessage(context, 'Trả hàng')),
              _MenuItem(Icons.account_balance_wallet_outlined, 'Sổ quỹ',
                  Colors.blue, () => _showMockMessage(context, 'Sổ quỹ')),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Nhóm chức năng: Hàng hoá
          _buildMenuSection(
            context,
            'HÀNG HOÁ',
            [
              _MenuItem(
                  Icons.inventory_2_outlined, 'Hàng hoá', AppColors.primary,
                  () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content: Text(
                        'Hãy dùng Tab Hàng hoá ở thanh điều hướng dưới!')));
              }),
              _MenuItem(Icons.check_box_outlined, 'Kiểm kho', Colors.teal,
                  () => _showMockMessage(context, 'Kiểm kho')),
              _MenuItem(
                  Icons.call_received_outlined,
                  'Nhập hàng',
                  AppColors.warning,
                  () => _showMockMessage(context, 'Nhập hàng')),
            ],
          ),
          const SizedBox(height: 12),

          // 4. Nhóm chức năng: Đối tác
          _buildMenuSection(
            context,
            'ĐỐI TÁC',
            [
              _MenuItem(Icons.people_outline, 'Khách hàng', AppColors.primary,
                  () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (context) => const CustomersPage()),
                );
              }),
              _MenuItem(
                  Icons.business_outlined,
                  'Nhà cung cấp',
                  Colors.blueGrey,
                  () => _showMockMessage(context, 'Nhà cung cấp')),
            ],
          ),
          const SizedBox(height: 12),

          // 5. Thiết lập hệ thống (Chỉ dành cho Admin/Supervisor)
          if (user?.isAdmin == true || user?.isSupervisor == true) ...[
            _buildMenuSection(
              context,
              'HỆ THỐNG',
              [
                _MenuItem(
                  Icons.people_alt_outlined,
                  l10n.accountManagement,
                  AppColors.primary,
                  () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const AccountManagementPage(),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          // 6. Chuyển đổi cửa hàng (Chỉ dành cho Admin/Supervisor)
          if (user?.isAdmin == true || user?.isSupervisor == true) ...[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHUYỂN ĐỔI CỬA HÀNG',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.black54,
                        letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 12),
                  storeNamesAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Text('Lỗi tải danh sách cửa hàng: $err'),
                    data: (storeNames) => DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      value: currentStore,
                      items: storeNames.entries.map((e) {
                        return DropdownMenuItem(
                          value: e.key,
                          child: Text(e.value),
                        );
                      }).toList(),
                      onChanged: (v) {
                        if (v != null) {
                          ref.read(selectedStoreIdProvider.notifier).state = v;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                content: Text(
                                    'Đã chuyển sang ${storeNames[v] ?? v}')),
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 7. Cài đặt chung & Đăng xuất
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.logout, color: AppColors.danger),
              title: Text(l10n.logoutAccount,
                  style: const TextStyle(
                      color: AppColors.danger, fontWeight: FontWeight.bold)),
              trailing:
                  const Icon(Icons.chevron_right, color: AppColors.danger),
              onTap: () => _showLogoutDialog(context, ref),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // Widget tạo danh mục chức năng
  Widget _buildMenuSection(
      BuildContext context, String header, List<_MenuItem> items) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 12,
                color: Colors.black54,
                letterSpacing: 0.5),
          ),
          const SizedBox(height: 16),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: items.length,
            itemBuilder: (context, idx) {
              final item = items[idx];
              return InkWell(
                onTap: item.onTap,
                child: Column(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: item.color.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(item.icon, color: item.color, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.title,
                      style:
                          const TextStyle(fontSize: 11, color: Colors.black87),
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    )
                  ],
                ),
              );
            },
          )
        ],
      ),
    );
  }

  void _showMockMessage(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Chức năng "$feature" đang được phát triển trong các bản nâng cấp sau.')),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.logout),
        content: Text(l10n.confirmLogoutApp),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c), child: Text(l10n.cancel)),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              ref.read(authProvider.notifier).logout();
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }
}

// Lớp phụ trợ đại diện cho một phần tử menu
class _MenuItem {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  _MenuItem(this.icon, this.title, this.color, this.onTap);
}
