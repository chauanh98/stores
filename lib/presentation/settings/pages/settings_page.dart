import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/auth/auth_providers.dart';

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
            child: ListTile(
              leading: const Icon(Icons.person),
              title: Text(user?.name ?? user?.username ?? 'Account'),
              subtitle: Text(
                  'Vai trò: ${user?.isSupervisor ? l10n.roleSupervisor : (user?.isAdmin ? l10n.roleAdmin : l10n.roleStaff)}'),
              trailing: TextButton.icon(
                icon: const Icon(Icons.logout, color: AppColors.danger),
                label: Text(l10n.logout,
                    style: const TextStyle(color: AppColors.danger)),
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
            ),
          ),
          const SizedBox(height: 16),
          if (user?.isAdmin == true || user?.isSupervisor == true)
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
}
