import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../application/auth/auth_providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);
    final currentStore = ref.watch(currentStoreIdProvider);
    final storeNamesAsync = ref.watch(availableStoresProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cài Đặt & Chuyển Đổi'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(user?.username ?? 'Khách'),
              subtitle: Text('Vai trò: ${user?.role == 'admin' ? 'Quản trị viên' : 'Nhân viên'}'),
              trailing: TextButton.icon(
                icon: const Icon(Icons.logout, color: Colors.red),
                label: const Text('Đăng xuất', style: TextStyle(color: Colors.red)),
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('Đăng xuất'),
                      content: const Text('Bạn có chắc chắn muốn đăng xuất?'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Hủy')),
                        FilledButton(
                          onPressed: () {
                            Navigator.pop(c);
                            ref.read(authProvider.notifier).logout();
                          },
                          child: const Text('Đăng xuất'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (user?.isAdmin == true)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chuyển Đổi Nhanh Cửa Hàng (Dành cho Admin)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    storeNamesAsync.when(
                      loading: () => const CircularProgressIndicator(),
                      error: (err, _) => Text('Lỗi tải danh sách: $err'),
                      data: (storeNames) => DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Chọn cửa hàng cần quản lý',
                          border: OutlineInputBorder(),
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
            ),
        ],
      ),
    );
  }
}