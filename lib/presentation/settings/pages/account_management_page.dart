import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../domain/entities/user_account.dart';
import '../../common/widgets/error_view.dart';
import '../../common/widgets/loading_indicator.dart';

class AccountManagementPage extends ConsumerStatefulWidget {
  const AccountManagementPage({super.key});

  @override
  ConsumerState<AccountManagementPage> createState() =>
      _AccountManagementPageState();
}

class _AccountManagementPageState extends ConsumerState<AccountManagementPage> {
  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsListProvider);
    final storesAsync = ref.watch(availableStoresProvider);
    final currentUser = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      appBar: AppBar(
        title: const Text('Quản lý tài khoản',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0.5,
      ),
      body: accountsAsync.when(
        data: (accounts) {
          if (accounts.isEmpty) {
            return const Center(child: Text('Không có tài khoản nào.'));
          }

          return storesAsync.when(
            data: (storeNames) {
              return ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: accounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final account = accounts[index];
                  final isMe = account.username == currentUser?.username;
                  final storeName =
                      storeNames[account.storeId] ?? account.storeId;

                  return Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE1E2E4)),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: account.isAdmin
                              ? const Color(0xFF0067AC).withOpacity(0.1)
                              : Colors.orange.withOpacity(0.1),
                          child: Icon(
                            account.isAdmin
                                ? Icons.admin_panel_settings
                                : Icons.person_outline,
                            color: account.isAdmin
                                ? const Color(0xFF0067AC)
                                : Colors.orange,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    account.username,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                      color: Colors.black87,
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
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: account.isAdmin
                                          ? const Color(0xFF0067AC)
                                              .withOpacity(0.06)
                                          : Colors.orange.withOpacity(0.06),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      account.isAdmin
                                          ? 'Quản trị viên'
                                          : 'Nhân viên',
                                      style: TextStyle(
                                        color: account.isAdmin
                                            ? const Color(0xFF0067AC)
                                            : Colors.orange,
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
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAccountFormDialog(context),
        backgroundColor: const Color(0xFF0067AC),
        foregroundColor: Colors.white,
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showAccountFormDialog(BuildContext context, {UserAccount? account}) {
    final isEdit = account != null;
    final usernameController =
        TextEditingController(text: account?.username ?? '');
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
              title: Text(isEdit ? 'Chỉnh sửa tài khoản' : 'Thêm tài khoản mới',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
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

                      // Role Dropdown
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        decoration: const InputDecoration(
                          labelText: 'Vai trò',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.security),
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'nhanvien', child: Text('Nhân viên')),
                          DropdownMenuItem(
                              value: 'admin', child: Text('Quản trị viên')),
                        ],
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedRole = value;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 16),

                      // Store Dropdown
                      DropdownButtonFormField<String>(
                        value: selectedStoreId,
                        decoration: const InputDecoration(
                          labelText: 'Gán cửa hàng',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.store),
                        ),
                        items: stores.entries.map((e) {
                          return DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          );
                        }).toList(),
                        onChanged: (value) {
                          if (value != null) {
                            setDialogState(() {
                              selectedStoreId = value;
                            });
                          }
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Hủy'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (formKey.currentState?.validate() ?? false) {
                      final username = usernameController.text.trim();

                      // Chuẩn bị dữ liệu lưu
                      final Map<String, dynamic> data = {
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
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          Navigator.pop(context); // Tắt màn hình loading
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Lỗi: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0067AC)),
                  child: const Text('Lưu'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _confirmDeleteAccount(BuildContext context, String username) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Xác nhận xóa',
              style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
              'Bạn có chắc chắn muốn xóa tài khoản "$username" khỏi hệ thống? Hành động này không thể hoàn tác.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Hủy'),
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
                      const SnackBar(
                        content: Text('Đã xóa tài khoản thành công!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context); // Tắt loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Lỗi khi xóa: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              child: const Text('Xóa'),
            ),
          ],
        );
      },
    );
  }
}
