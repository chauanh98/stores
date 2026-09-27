import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/core/utils/store_resolver_helper.dart';

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
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0.5,
      ),
      body: accountsAsync.when(
        data: (accounts) {
          // Admin xem được tất cả tài khoản
          // Supervisor chỉ xem các tài khoản cùng chi nhánh của mình và tài khoản Admin
          final visibleAccounts = accounts.where((a) {
            if (currentUser?.isAdmin == true) return true;
            if (currentUser?.isSupervisor == true) {
              return a.storeId == currentUser?.storeId ||
                  a.isAllStores ||
                  a.isAdmin;
            }
            return a.username == currentUser?.username;
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
                  final isAllStores = account.isAllStores ||
                      account.storeId == 'all' ||
                      account.isAdmin;
                  final storeName = (account.isAdmin || isAllStores)
                      ? 'Toàn bộ chi nhánh (Toàn hệ thống)'
                      : StoreResolverHelper.resolveStoreName(account.storeId,
                          storeNames: storeNames);

                  Color roleColor;
                  Color roleBgColor;
                  IconData roleIcon;
                  String roleLabel;

                  if (account.isAdmin) {
                    roleColor = AppColors.primary;
                    roleBgColor = AppColors.primary.withOpacity(0.1);
                    roleIcon = Icons.admin_panel_settings;
                    roleLabel = '👑 Quản trị viên (Chủ shop)';
                  } else if (account.isSupervisor) {
                    roleColor = AppColors.supervisor;
                    roleBgColor = AppColors.supervisor.withOpacity(0.1);
                    roleIcon = Icons.verified_user;
                    roleLabel = '👔 Cửa hàng trưởng';
                  } else {
                    roleColor = AppColors.orangeDark;
                    roleBgColor = AppColors.warning.withOpacity(0.1);
                    roleIcon = Icons.person_outline;
                    roleLabel = '🧑‍💼 Nhân viên';
                  }

                  // Bảo vệ phân quyền ngang cấp: Admin không được sửa/xóa Admin khác
                  final canEditThis = (currentUser?.isAdmin == true &&
                          (!account.isAdmin || isMe)) ||
                      (currentUser?.isSupervisor == true &&
                          account.isStaff &&
                          account.storeId == currentUser?.storeId) ||
                      isMe;
                  final canDeleteThis = !isMe &&
                      !account.isAdmin &&
                      (currentUser?.isAdmin == true ||
                          (currentUser?.isSupervisor == true &&
                              account.isStaff &&
                              account.storeId == currentUser?.storeId));

                  return Container(
                    decoration: BoxDecoration(
                      color: AppColors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: roleBgColor,
                          child: Icon(roleIcon, color: roleColor),
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
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (isMe) ...[
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.grey200,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Text(
                                        'Tôi',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: AppColors.textSecondary,
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
                                      fontSize: 12,
                                      color: AppColors.textTertiary),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                runSpacing: 4,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: roleBgColor,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      roleLabel,
                                      style: TextStyle(
                                        color: roleColor,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isAllStores
                                          ? AppColors.primary.withOpacity(0.06)
                                          : AppColors.grey100,
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: isAllStores
                                            ? AppColors.primary.withOpacity(0.2)
                                            : AppColors.borderLight,
                                        width: 0.8,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          isAllStores
                                              ? Icons.hub_outlined
                                              : Icons.store_outlined,
                                          size: 13,
                                          color: isAllStores
                                              ? AppColors.primary
                                              : AppColors.textSecondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          storeName,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: isAllStores
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isAllStores
                                                ? AppColors.primary
                                                : AppColors.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              )
                            ],
                          ),
                        ),
                        if (canEditThis || canDeleteThis)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (canEditThis)
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined,
                                      color: AppColors.primary),
                                  onPressed: () => _showAccountFormDialog(
                                      context,
                                      account: account),
                                  tooltip: 'Chỉnh sửa tài khoản',
                                ),
                              if (canDeleteThis)
                                IconButton(
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppColors.danger,
                                  ),
                                  onPressed: () => _confirmDeleteAccount(
                                      context, account.username),
                                  tooltip: 'Xóa tài khoản',
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
      floatingActionButton:
          (currentUser?.isAdmin == true || currentUser?.isSupervisor == true)
              ? ScrollAwareFab(
                  scrollController: _scrollController,
                  child: FloatingActionButton(
                    onPressed: () => _showAccountFormDialog(context),
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.white,
                    child: const Icon(Icons.add),
                  ),
                )
              : null,
    );
  }

  void _showAccountFormDialog(BuildContext context, {UserAccount? account}) {
    final l10n = AppLocalizations.of(context)!;
    final currentUser = ref.read(authProvider);
    final canManageAll = currentUser?.isAdmin == true;
    final isSupervisor = currentUser?.isSupervisor ?? false;

    // Chặn tuyệt đối nếu cố tình mở form sửa tài khoản Admin khác
    if (account != null &&
        account.isAdmin &&
        account.username != currentUser?.username) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Không có quyền chỉnh sửa tài khoản Quản trị viên khác!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    final isEdit = account != null;
    final isSelfAdmin =
        isEdit && account.isAdmin && account.username == currentUser?.username;
    final canChangeRole = canManageAll && !isSelfAdmin;
    final usernameController =
        TextEditingController(text: account?.username ?? '');
    final displayNameController =
        TextEditingController(text: account?.displayName ?? '');
    final passwordController = TextEditingController();
    String selectedRole =
        (account?.isAdmin == true) ? 'admin' : (account?.role ?? 'nhanvien');

    // Tải danh sách cửa hàng
    final stores = ref.read(availableStoresProvider).value ?? {};
    String selectedStoreId = (account != null &&
            account.storeId.isNotEmpty &&
            account.storeId != 'all')
        ? account.storeId
        : (currentUser?.isSupervisor == true
            ? currentUser!.storeId
            : (stores.keys.isNotEmpty ? stores.keys.first : 'store_001'));

    final currentRoleLabel = (account != null)
        ? (account.isAdmin
            ? 'Quản trị viên (Chủ shop)'
            : (account.isSupervisor ? 'Cửa hàng trưởng' : 'Nhân viên'))
        : '';
    final currentRoleColor = (account != null)
        ? (account.isAdmin
            ? AppColors.primary
            : (account.isSupervisor
                ? AppColors.supervisor
                : AppColors.orangeDark))
        : AppColors.grey400;
    final currentRoleIcon = (account != null)
        ? (account.isAdmin
            ? Icons.admin_panel_settings
            : (account.isSupervisor
                ? Icons.verified_user
                : Icons.person_outline))
        : Icons.person;
    final isAccountAllStores = account != null &&
        (account.isAdmin || account.isAllStores || account.storeId == 'all');
    final currentStoreLabel = (account != null)
        ? (isAccountAllStores
            ? 'Toàn bộ chi nhánh (Toàn hệ thống)'
            : StoreResolverHelper.resolveStoreName(account.storeId,
                storeNames: stores))
        : '';

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
                      // Thẻ thông tin hiện tại (Chỉ hiển thị khi chỉnh sửa)
                      if (account != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.softBlueSurface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.softBlueBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.info_outline,
                                      size: 16, color: AppColors.primary),
                                  SizedBox(width: 6),
                                  Text(
                                    'Thông tin hiện tại',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Divider(
                                  height: 1, color: AppColors.softBlueBorder),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(currentRoleIcon,
                                      size: 14, color: currentRoleColor),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Vai trò hiện tại: ',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary),
                                  ),
                                  Text(
                                    currentRoleLabel,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: currentRoleColor,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Row(
                                children: [
                                  Icon(
                                    isAccountAllStores
                                        ? Icons.hub_outlined
                                        : Icons.store_outlined,
                                    size: 14,
                                    color: AppColors.textSecondary,
                                  ),
                                  const SizedBox(width: 6),
                                  const Text(
                                    'Chi nhánh hiện tại: ',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary),
                                  ),
                                  Expanded(
                                    child: Text(
                                      currentStoreLabel,
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

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

                      // Role Dropdown (Chỉ Admin mới có quyền gán vai trò, không tự hạ vai trò admin của mình)
                      DropdownButtonFormField<String>(
                        value: selectedRole,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Vai trò',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.security),
                          helperText: isSelfAdmin
                              ? 'Không thể thay đổi vai trò của Quản trị viên'
                              : (canManageAll
                                  ? null
                                  : 'Chỉ Quản trị viên mới có quyền đổi vai trò này'),
                        ),
                        items: [
                          const DropdownMenuItem(
                              value: 'nhanvien',
                              child: Text('Nhân viên (Thu ngân / Bán hàng)',
                                  overflow: TextOverflow.ellipsis)),
                          const DropdownMenuItem(
                              value: 'supervisor',
                              child: Text('Cửa hàng trưởng (Supervisor)',
                                  overflow: TextOverflow.ellipsis)),
                          if (canManageAll)
                            const DropdownMenuItem(
                                value: 'admin',
                                child: Text(
                                    'Quản trị viên (Chủ shop - Toàn chuỗi)',
                                    overflow: TextOverflow.ellipsis)),
                        ],
                        onChanged: canChangeRole
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

                      // Store Assignment:
                      // Nếu là Admin: Quản lý toàn bộ chi nhánh (Toàn hệ thống)
                      // Nếu là Supervisor hoặc Nhân viên: Chọn chi nhánh cụ thể
                      if (selectedRole == 'admin' ||
                          selectedRole == 'owner') ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.2)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.hub_outlined,
                                  color: AppColors.primary, size: 24),
                              SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Toàn bộ chi nhánh (Toàn hệ thống)',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    SizedBox(height: 2),
                                    Text(
                                      'Chủ shop / Quản trị viên có quyền truy cập và quản lý toàn bộ chi nhánh.',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        DropdownButtonFormField<String>(
                          value: stores.containsKey(selectedStoreId)
                              ? selectedStoreId
                              : (stores.keys.isNotEmpty
                                  ? stores.keys.first
                                  : 'store_001'),
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: selectedRole == 'supervisor'
                                ? 'Chi nhánh phụ trách *'
                                : 'Chi nhánh làm việc *',
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.store),
                            helperText: canManageAll
                                ? null
                                : (isSupervisor
                                    ? 'Cố định tại chi nhánh của bạn'
                                    : null),
                          ),
                          items: stores.entries.map((e) {
                            return DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value,
                                  overflow: TextOverflow.ellipsis),
                            );
                          }).toList(),
                          onChanged: canManageAll
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
                      final String finalStoreId =
                          (selectedRole == 'admin' || selectedRole == 'owner')
                              ? 'all'
                              : (stores.containsKey(selectedStoreId)
                                  ? selectedStoreId
                                  : (stores.keys.isNotEmpty
                                      ? stores.keys.first
                                      : 'store_001'));

                      // Chuẩn bị dữ liệu lưu
                      final Map<String, dynamic> data = {
                        'displayName': displayNameController.text.trim(),
                        'role': selectedRole,
                        'storeId': finalStoreId,
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

                      if (!context.mounted) return;

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

                        final currentUser = ref.read(authProvider);
                        if (currentUser?.username == username &&
                            passwordController.text.isNotEmpty) {
                          await ref
                              .read(authProvider.notifier)
                              .updateSavedPassword(passwordController.text);
                        }

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
    final accounts = ref.read(accountsListProvider).value ?? [];
    final targetAccount = accounts.firstWhere(
      (a) => a.username == username,
      orElse: () => UserAccount(
        username: username,
        displayName: username,
        role: 'unknown',
        storeId: '',
      ),
    );
    if (targetAccount.isAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Không thể xóa tài khoản Quản trị viên!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

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
