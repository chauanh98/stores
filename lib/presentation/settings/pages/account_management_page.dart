import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../domain/entities/user_account.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/loading_indicator.dart';
import '../../common/widgets/scroll_aware_fab.dart';

class AccountManagementPage extends ConsumerStatefulWidget {
  const AccountManagementPage({super.key});

  @override
  ConsumerState<AccountManagementPage> createState() =>
      _AccountManagementPageState();
}

class _AccountManagementPageState extends ConsumerState<AccountManagementPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final accountsAsync = ref.watch(accountsListProvider);
    final storesAsync = ref.watch(availableStoresProvider);
    final currentUser = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(l10n.accountManagement,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: accountsAsync.when(
        data: (accounts) {
          // Nếu người dùng không phải Supervisor (ví dụ Admin), ẩn hoàn toàn các tài khoản Supervisor
          final visibleAccounts = accounts.where((a) {
            if (currentUser?.isSupervisor != true && a.isSupervisor) {
              return false;
            }
            return true;
          }).toList();

          if (visibleAccounts.isEmpty) {
            return Center(child: Text(l10n.noAccountsFound));
          }

          return storesAsync.when(
            data: (storeNames) {
              return ListView.separated(
                controller: _scrollController,
                padding: const EdgeInsets.all(16),
                itemCount: visibleAccounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final account = visibleAccounts[index];
                  final isMe = account.username == currentUser?.username;
                  final storeName =
                      storeNames[account.storeId] ?? account.storeId;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: account.isSupervisor
                              ? Colors.purple.withOpacity(0.1)
                              : (account.isAdmin
                                  ? AppColors.primary.withOpacity(0.1)
                                  : Colors.orange.withOpacity(0.1)),
                          child: Icon(
                            account.isSupervisor
                                ? Icons.verified_user
                                : (account.isAdmin
                                    ? Icons.admin_panel_settings
                                    : Icons.person_outline),
                            color: account.isSupervisor
                                ? Colors.purple
                                : (account.isAdmin
                                    ? AppColors.primary
                                    : Colors.orange),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      account.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.black87,
                                      ),
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade200,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Tôi',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Colors.black54,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    )
                                  ]
                                ],
                              ),
                              if (account.displayName != null &&
                                  account.displayName!.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  '@${account.username}',
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black45),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: account.isSupervisor
                                          ? Colors.purple.withOpacity(0.08)
                                          : (account.isAdmin
                                              ? AppColors.primary
                                                  .withOpacity(0.06)
                                              : AppColors.warning
                                                  .withOpacity(0.06)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      account.isSupervisor
                                          ? l10n.roleSupervisor
                                          : (account.isAdmin
                                              ? l10n.roleAdmin
                                              : l10n.roleStaff),
                                      style: TextStyle(
                                        color: account.isSupervisor
                                            ? AppColors.supervisor
                                            : (account.isAdmin
                                                ? AppColors.primary
                                                : AppColors.warning),
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      storeName,
                                      style: const TextStyle(
                                          fontSize: 12, color: Colors.black54),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  color: Colors.blue),
                              onPressed: () => _showAccountFormDialog(context,
                                  account: account),
                              tooltip: 'Chỉnh sửa tài khoản',
                            ),
                            IconButton(
                              icon: Icon(
                                Icons.delete_outline,
                                color: isMe
                                    ? Colors.grey.shade300
                                    : Colors.redAccent,
                              ),
                              onPressed: isMe
                                  ? null
                                  : () => _confirmDeleteAccount(
                                      context, account.username),
                              tooltip: isMe
                                  ? 'Không thể xóa chính bạn'
                                  : 'Xóa tài khoản',
                            ),
                          ],
                        )
                      ],
                    ),
                  );
                },
              );
            },
            loading: () => const Center(child: LoadingIndicator()),
            error: (e, _) => Center(child: ErrorView(e)),
          );
        },
        loading: () => const Center(child: LoadingIndicator()),
        error: (e, _) => Center(child: ErrorView(e)),
      ),
      floatingActionButton: ScrollAwareFab(
        scrollController: _scrollController,
        child: FloatingActionButton(
          onPressed: () => _showAccountFormDialog(context),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  void _showAccountFormDialog(BuildContext context, {UserAccount? account}) {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.read(authProvider);
    final isSupervisor = currentUser?.isSupervisor ?? false;

    final isEdit = account != null;
    final usernameController =
        TextEditingController(text: account?.username ?? '');
    final displayNameController =
        TextEditingController(text: account?.displayName ?? '');
    final passwordController = TextEditingController();
    String selectedRole = account?.role ?? 'nhanvien';

    // Tải danh sách cửa hàng
    final stores = ref.read(availableStoresProvider).value ?? {};
    String selectedStoreId = account?.storeId ??
        (stores.keys.isNotEmpty ? stores.keys.first : 'store_001');

    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(isEdit ? l10n.editAccount : l10n.addAccount,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Display Name
                      TextFormField(
                        controller: displayNameController,
                        decoration: const InputDecoration(
                          labelText: 'Họ tên hiển thị (VD: Nguyễn Văn A)',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Username
                      TextFormField(
                        controller: usernameController,
                        enabled: !isEdit,
                        decoration: const InputDecoration(
                          labelText: 'Tên đăng nhập',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Vui lòng nhập tên đăng nhập';
                          }
                          final clean = value.trim();
                          if (clean.contains(' ')) {
                            return 'Tên đăng nhập không được chứa dấu cách';
                          }
                          if (!isEdit) {
                            // Check trùng tên đăng nhập
                            final accounts =
                                ref.read(accountsListProvider).value ?? [];
                            final exists = accounts.any((a) =>
                                a.username.toLowerCase() ==
                                clean.toLowerCase());
                            if (exists) {
                              return 'Tên đăng nhập đã tồn tại';
                            }
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Password
                      TextFormField(
                        controller: passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: isEdit
                              ? 'Mật khẩu mới (bỏ trống nếu giữ nguyên)'
                              : 'Mật khẩu',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.lock),
                        ),
                        validator: (value) {
                          if (!isEdit && (value == null || value.isEmpty)) {
                            return 'Vui lòng nhập mật khẩu';
                          }
                          if (value != null &&
                              value.isNotEmpty &&
                              value.length < 4) {
                            return 'Mật khẩu phải từ 4 ký tự trở lên';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),

                      // Role Dropdown (Chỉ Supervisor mới có quyền đổi)
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Vai trò',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.security),
                          helperText: isSupervisor
                              ? null
                              : l10n.onlySupervisorCanEditRole,
                        ),
                        items: [
                          DropdownMenuItem(
                              value: 'nhanvien',
                              child: Text(l10n.roleStaff,
                                  overflow: TextOverflow.ellipsis)),
                          DropdownMenuItem(
                              value: 'admin',
                              child: Text(l10n.roleAdmin,
                                  overflow: TextOverflow.ellipsis)),
                          if (isSupervisor)
                            DropdownMenuItem(
                                value: 'supervisor',
                                child: Text(l10n.roleSupervisor,
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: isSupervisor
                            ? (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedRole = value;
                                  });
                                }
                              }
                            : null,
                      ),
                      const SizedBox(height: 16),

                      // Store Dropdown (Chỉ Supervisor mới có quyền đổi/gán cửa hàng)
                      DropdownButtonFormField<String>(
                        value: selectedStoreId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Gán cửa hàng',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.store),
                          helperText: isSupervisor
                              ? null
                              : l10n.onlySupervisorCanAssignStore,
                        ),
                        items: stores.entries.map((e) {
                          return DropdownMenuItem(
                            value: e.key,
                            child:
                                Text(e.value, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: isSupervisor
                            ? (value) {
                                if (value != null) {
                                  setDialogState(() {
                                    selectedStoreId = value;
                                  });
                                }
                              }
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(l10n.cancel),
                ),
                FilledButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final username = usernameController.text.trim();

                      // Chuẩn bị dữ liệu lưu
                      final Map<String, dynamic> data = {
                        'displayName': displayNameController.text.trim(),
                        'role': selectedRole,
                        'storeId': selectedStoreId,
                      };

                      if (isEdit) {
                        // Nếu sửa, chỉ cập nhật password nếu có nhập
                        if (passwordController.text.isNotEmpty) {
                          data['password'] = passwordController.text;
                        } else {
                          // Lấy lại mật khẩu cũ để ghi đè (hoặc lấy từ DB)
                          // Vì database là dạng phẳng, set sẽ ghi đè toàn bộ node nên cần giữ password
                          // Chúng ta sẽ fetch trực tiếp từ tài khoản hiện tại
                          try {
                            final oldPassword = await ref
                                .read(authRemoteDataSourceProvider)
                                .getAccountPassword(username);
                            data['password'] = oldPassword ?? '1234';
                          } catch (e) {
                            data['password'] = '1234';
                          }
                        }
                      } else {
                        data['password'] = passwordController.text;
                      }

                      // Hiện màn hình loading
                      showDialog(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) =>
                            const Center(child: CircularProgressIndicator()),
                      );

                      try {
                        await ref
                            .read(authRemoteDataSourceProvider)
                            .saveAccount(username, data);

                        if (context.mounted) {
                          Navigator.pop(context); // Tắt màn hình loading
                          Navigator.pop(context); // Tắt form dialog
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(isEdit
                                  ? 'Cập nhật tài khoản thành công!'
                                  : 'Tạo tài khoản thành công!'),
                              backgroundColor: AppColors.success,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context); // Tắt màn hình loading
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('${l10n.importError}: $e'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      }
                    }
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary),
                  child: Text(l10n.save),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAccount(BuildContext context, String username) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.confirmDeleteAccountTitle,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
              'Bạn có chắc chắn muốn xóa tài khoản "$username" khỏi hệ thống? Hành động này không thể hoàn tác.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context); // Tắt dialog xác nhận

                // Show loading indicator
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      const Center(child: CircularProgressIndicator()),
                );

                try {
                  await ref
                      .read(authRemoteDataSourceProvider)
                      .deleteAccount(username);

                  if (context.mounted) {
                    Navigator.pop(context); // Tắt loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.accountDeletedSuccess),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // Tắt loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Lỗi khi xóa: $e'),
                        backgroundColor: AppColors.danger,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
  }
}
