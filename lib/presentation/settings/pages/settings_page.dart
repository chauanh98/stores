import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/auth/auth_providers.dart';
import 'store_payment_settings_page.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider);
    final currentStore = ref.watch(currentStoreIdProvider);
    final storeNamesAsync = ref.watch(availableStoresProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.person, size: 36, color: AppColors.primary),
                    title: Text(user?.name ?? user?.username ?? 'Account',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text(
                        'Vai trò: ${user?.isSupervisor == true ? l10n.roleSupervisor : (user?.isAdmin == true ? l10n.roleAdmin : l10n.roleStaff)}'),
                  ),
                  const Divider(height: 1, color: AppColors.divider),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.lock_reset, size: 18, color: AppColors.primary),
                        label: const Text('Đổi mật khẩu',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                        onPressed: () {
                          if (user?.username != null) {
                            _showChangePasswordDialog(context, ref, user!.username);
                          }
                        },
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.logout, size: 18, color: AppColors.danger),
                        label: Text(l10n.logout,
                            style: const TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 13)),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: AppColors.danger),
                        ),
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: Text(l10n.logout),
                              content: Text(l10n.confirmLogout),
                              actions: [
                                TextButton(
                                    onPressed: () => Navigator.pop(c),
                                    child: Text(l10n.cancel)),
                                FilledButton(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: AppColors.danger),
                                  onPressed: () {
                                    Navigator.pop(c);
                                    ref.read(authProvider.notifier).logout();
                                  },
                                  child: Text(l10n.logout),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (user?.isSupervisor == true) ...[
            Card(
              child: ListTile(
                leading: const Icon(Icons.qr_code_2, color: AppColors.primary),
                title: const Text(
                  'Cấu Hình Hóa Đơn & Nhận Tiền (VietQR)',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('Quản lý tài khoản ngân hàng, thông tin shop & mẫu hóa đơn'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const StorePaymentSettingsPage(),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (user?.canSwitchStore == true)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chuyển Đổi Nhanh Cửa Hàng',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
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
                            ref.read(selectedStoreIdProvider.notifier).state =
                                v;
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
            ),
        ],
      ),
    );
  }

  void _showChangePasswordDialog(
      BuildContext context, WidgetRef ref, String username) {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Đổi Mật Khẩu',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: oldPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu hiện tại',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Vui lòng nhập mật khẩu hiện tại'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: newPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mật khẩu mới',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock_reset),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Vui lòng nhập mật khẩu mới';
                    }
                    if (v.length < 4) {
                      return 'Mật khẩu mới phải từ 4 ký tự trở lên';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmPasswordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Xác nhận mật khẩu mới',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.check_circle_outline),
                  ),
                  validator: (v) {
                    if (v != newPasswordController.text) {
                      return 'Xác nhận mật khẩu không khớp';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Hủy'),
            ),
            FilledButton(
              onPressed: () async {
                if (formKey.currentState?.validate() ?? false) {
                  showDialog(
                    context: dialogContext,
                    barrierDismissible: false,
                    builder: (_) =>
                        const Center(child: CircularProgressIndicator()),
                  );

                  try {
                    await ref
                        .read(authRemoteDataSourceProvider)
                        .updatePassword(
                          username,
                          oldPasswordController.text,
                          newPasswordController.text,
                        );
                    if (context.mounted) {
                      Navigator.pop(dialogContext); // dismiss loading
                      Navigator.pop(dialogContext); // dismiss form
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Đổi mật khẩu thành công!'),
                          backgroundColor: AppColors.success,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      Navigator.pop(dialogContext); // dismiss loading
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              'Lỗi: ${e.toString().replaceAll('Exception: ', '')}'),
                          backgroundColor: AppColors.danger,
                        ),
                      );
                    }
                  }
                }
              },
              style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary),
              child: const Text('Lưu mật khẩu'),
            ),
          ],
        );
      },
    );
  }
}
