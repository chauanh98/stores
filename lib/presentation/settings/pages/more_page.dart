import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/auth/auth_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../customers/pages/customers_page.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final currentStore = ref.watch(currentStoreIdProvider);
    final storeNamesAsync = ref.watch(availableStoresProvider);
    final selectedBranchIds = ref.watch(selectedBranchesProvider);

    // Tên chi nhánh hiện tại
    String branchName = 'Tất cả chi nhánh';
    if (selectedBranchIds.length == 1) {
      final mockBranches = getMockBranches(currentStore);
      branchName = mockBranches.firstWhere((b) => b.id == selectedBranchIds.first).name;
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Nhiều hơn', style: TextStyle(fontWeight: FontWeight.bold)),
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
                  backgroundColor: const Color(0xFF0067AC),
                  child: Text(
                    (user?.username ?? 'K').substring(0, 1).toUpperCase(),
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
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
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: Colors.black87),
                            ),
                            loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                            error: (_, __) => const Text('Lỗi tải tên cửa hàng'),
                          ),
                      const SizedBox(height: 4),
                      Text(
                        'Tài khoản: ${user?.username ?? 'Nhân viên'}',
                        style: const TextStyle(color: Colors.black54, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Chi nhánh: $branchName',
                        style: const TextStyle(color: Color(0xFF0067AC), fontSize: 12, fontWeight: FontWeight.w500),
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
              _MenuItem(Icons.storefront_outlined, 'Bán hàng', const Color(0xFF0067AC), () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hãy dùng Tab Bán hàng ở thanh điều hướng dưới!')));
              }),
              _MenuItem(Icons.receipt_long_outlined, 'Hoá đơn', Colors.orange, () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hãy dùng Tab Hoá đơn ở thanh điều hướng dưới!')));
              }),
              _MenuItem(Icons.assignment_outlined, 'Đặt hàng', Colors.teal, () => _showMockMessage(context, 'Đặt hàng')),
              _MenuItem(Icons.assignment_return_outlined, 'Trả hàng', Colors.red, () => _showMockMessage(context, 'Trả hàng')),
              _MenuItem(Icons.account_balance_wallet_outlined, 'Sổ quỹ', Colors.blue, () => _showMockMessage(context, 'Sổ quỹ')),
            ],
          ),
          const SizedBox(height: 12),

          // 3. Nhóm chức năng: Hàng hoá
          _buildMenuSection(
            context,
            'HÀNG HOÁ',
            [
              _MenuItem(Icons.inventory_2_outlined, 'Hàng hoá', const Color(0xFF0067AC), () {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Hãy dùng Tab Hàng hoá ở thanh điều hướng dưới!')));
              }),
              _MenuItem(Icons.check_box_outlined, 'Kiểm kho', Colors.teal, () => _showMockMessage(context, 'Kiểm kho')),
              _MenuItem(Icons.call_received_outlined, 'Nhập hàng', Colors.orange, () => _showMockMessage(context, 'Nhập hàng')),
            ],
          ),
          const SizedBox(height: 12),

          // 4. Nhóm chức năng: Đối tác
          _buildMenuSection(
            context,
            'ĐỐI TÁC',
            [
              _MenuItem(Icons.people_outline, 'Khách hàng', const Color(0xFF0067AC), () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => const CustomersPage()),
                );
              }),
              _MenuItem(Icons.business_outlined, 'Nhà cung cấp', Colors.blueGrey, () => _showMockMessage(context, 'Nhà cung cấp')),
            ],
          ),
          const SizedBox(height: 12),

          // 5. Chuyển đổi cửa hàng (Chỉ dành cho Admin)
          if (user?.isAdmin == true) ...[
            Container(
              color: Colors.white,
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHUYỂN ĐỔI CỬA HÀNG (ADMIN)',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 12),
                  storeNamesAsync.when(
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (err, _) => Text('Lỗi tải danh sách cửa hàng: $err'),
                    data: (storeNames) => DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
                            SnackBar(content: Text('Đã chuyển sang ${storeNames[v] ?? v}')),
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

          // 6. Cài đặt chung & Đăng xuất
          Container(
            color: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Đăng xuất tài khoản', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
              trailing: const Icon(Icons.chevron_right, color: Colors.red),
              onTap: () => _showLogoutDialog(context, ref),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // Widget tạo danh mục chức năng
  Widget _buildMenuSection(BuildContext context, String header, List<_MenuItem> items) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            header,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.black54, letterSpacing: 0.5),
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
                      style: const TextStyle(fontSize: 11, color: Colors.black87),
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
      SnackBar(content: Text('Chức năng "$feature" đang được phát triển trong các bản nâng cấp sau.')),
    );
  }

  void _showLogoutDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Đăng xuất'),
        content: const Text('Bạn có chắc chắn muốn đăng xuất khỏi ứng dụng?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
          FilledButton(
            onPressed: () {
              Navigator.pop(c);
              ref.read(authProvider.notifier).logout();
            },
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFF0067AC)),
            child: const Text('Đăng xuất'),
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
