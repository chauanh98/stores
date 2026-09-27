import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/core/theme/app_colors.dart';
import 'package:stores/core/utils/store_resolver_helper.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../core/services/filter_storage_service.dart';
import '../../attendance/pages/attendance_check_in_page.dart';
import '../../attendance/pages/live_attendance_dashboard_page.dart';
import '../../attendance/pages/shift_config_page.dart';
import '../../customers/pages/customers_page.dart';
import '../../inventories/pages/inter_store_transfer_page.dart';
import '../../inventories/pages/stock_in_receipts_page.dart';
import '../../orders/pages/invoices_page.dart';
import '../../products/pages/categories_management_page.dart';
import '../../suppliers/pages/suppliers_page.dart';
import 'account_management_page.dart';
import 'store_payment_settings_page.dart';

class MorePage extends ConsumerWidget {
  const MorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider);
    final currentStore = ref.watch(currentStoreIdProvider);
    final storeNamesAsync = ref.watch(availableStoresProvider);

    // Tên chi nhánh của người dùng (nếu là nhân viên / giám sát) hoặc chi nhánh đang làm việc
    final allStores = storeNamesAsync.value ?? {};
    final activeStoreName = allStores[currentStore] ??
        StoreResolverHelper.resolveStoreName(currentStore,
            storeNames: allStores);
    final userAssignedStoreName =
        (user != null && user.storeId.isNotEmpty && user.storeId != 'all')
            ? StoreResolverHelper.resolveStoreName(user.storeId,
                storeNames: allStores)
            : activeStoreName;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.moreOptions,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        child: Column(
          children: [
            // ==========================================
            // BLOCK 1: THÔNG TIN CỬA HÀNG & TÀI KHOẢN
            // ==========================================
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.black.withOpacity(0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 28,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          (user?.username ?? 'K').substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ref.watch(currentStoreNameProvider).when(
                                  data: (name) => Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  loading: () => const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  ),
                                  error: (_, __) => Text(l10n.importError),
                                ),
                            const SizedBox(height: 4),
                            Text(
                              'Tài khoản: ${user?.username ?? 'Nhân viên'}',
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    user?.isAdmin == true
                                        ? '👑 Quản trị viên (Toàn hệ thống)'
                                        : user?.isSupervisor == true
                                            ? 'Giám sát'
                                            : 'Nhân viên',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: (user?.isAdmin == true)
                                        ? AppColors.primary.withOpacity(0.08)
                                        : AppColors.grey100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: (user?.isAdmin == true)
                                        ? Border.all(
                                            color: AppColors.primary
                                                .withOpacity(0.25),
                                            width: 0.8,
                                          )
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (user?.isAdmin == true) ...[
                                        const Icon(
                                          Icons.hub_outlined,
                                          size: 12,
                                          color: AppColors.primary,
                                        ),
                                        const SizedBox(width: 4),
                                      ],
                                      Text(
                                        (user?.isAdmin == true)
                                            ? 'Toàn bộ chi nhánh'
                                            : 'Chi nhánh: $userAssignedStoreName',
                                        style: TextStyle(
                                          color: (user?.isAdmin == true)
                                              ? AppColors.primary
                                              : AppColors.grey800,
                                          fontSize: 11,
                                          fontWeight: (user?.isAdmin == true)
                                              ? FontWeight.bold
                                              : FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // Nút chuyển đổi chi nhánh / cửa hàng (Supervisor / Admin có quyền)
                  if (user?.isAdmin == true) ...[
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    const Text(
                      'CHUYỂN ĐỔI CỬA HÀNG',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    storeNamesAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (err, _) =>
                          Text('Lỗi tải danh sách cửa hàng: $err'),
                      data: (storeNames) => DropdownButtonFormField<String>(
                        isExpanded: true,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 12, vertical: 10),
                        ),
                        value: storeNames.containsKey(currentStore)
                            ? currentStore
                            : (storeNames.isNotEmpty
                                ? storeNames.keys.first
                                : null),
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
                            final user = ref.read(authProvider);
                            if (user != null && user.canSwitchStore) {
                              ref
                                  .read(filterStorageServiceProvider)
                                  .saveSelectedStore(v, user.username);
                            }
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    'Đã chuyển sang ${storeNames[v] ?? v}'),
                              ),
                            );
                          }
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ==========================================
            // BLOCK 2: QUẢN LÝ ĐỐI TÁC
            // ==========================================
            _buildCardBlock(
              headerTitle: 'QUẢN LÝ ĐỐI TÁC',
              headerIcon: Icons.handshake_outlined,
              headerColor: AppColors.primary,
              children: [
                _buildMenuTile(
                  icon: Icons.people_outline,
                  title: 'Khách hàng',
                  subtitle: 'Danh sách và công nợ khách hàng',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const CustomersPage()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 52),
                _buildMenuTile(
                  icon: Icons.storefront_outlined,
                  title: 'Nhà cung cấp',
                  subtitle: 'Quản lý đối tác và công nợ NCC',
                  color: AppColors.chartTeal,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SuppliersPage()),
                    );
                  },
                ),
              ],
            ),

            // ==========================================
            // BLOCK 3: NGHIỆP VỤ KHO & BÁN HÀNG
            // ==========================================
            _buildCardBlock(
              headerTitle: 'NGHIỆP VỤ KHO & BÁN HÀNG',
              headerIcon: Icons.inventory_2_outlined,
              headerColor: AppColors.warning,
              children: [
                _buildMenuTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Phiếu nhập kho',
                  subtitle: 'Lịch sử & quản lý phiếu nhập hàng',
                  color: AppColors.warning,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const StockInReceiptsPage()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 52),
                _buildMenuTile(
                  icon: Icons.swap_horiz_outlined,
                  title: 'Chuyển kho',
                  subtitle: 'Điều chuyển hàng hóa giữa các chi nhánh',
                  color: AppColors.chartIndigo,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const InterStoreTransferPage()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 52),
                _buildMenuTile(
                  icon: Icons.receipt_long_outlined,
                  title: 'Hóa đơn & Sổ quỹ',
                  subtitle: 'Lịch sử hóa đơn, trả hàng và thu nợ',
                  color: AppColors.success,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const InvoicesPage()),
                    );
                  },
                ),
                const Divider(height: 1, indent: 52),
                _buildMenuTile(
                  icon: Icons.category_outlined,
                  title: 'Quản lý nhóm hàng',
                  subtitle: 'Cây phân cấp danh mục hàng hóa',
                  color: AppColors.warning,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => const CategoriesManagementPage()),
                    );
                  },
                ),
              ],
            ),

            // ==========================================
            // BLOCK: QUẢN LÝ CA & CHẤM CÔNG
            // ==========================================
            _buildCardBlock(
              headerTitle: 'QUẢN LÝ CA & CHẤM CÔNG',
              headerIcon: Icons.access_time_filled_outlined,
              headerColor: AppColors.primary,
              children: [
                if (user?.requiresAttendance == true)
                  _buildMenuTile(
                    icon: Icons.fingerprint,
                    title: 'Chấm công nhân viên',
                    subtitle: 'Điểm danh vào/ra ca & xác thực vị trí GPS',
                    color: AppColors.primary,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AttendanceCheckInPage(),
                        ),
                      );
                    },
                  ),
                if (user?.isAdmin == true || user?.isSupervisor == true) ...[
                  if (user?.requiresAttendance == true)
                    const Divider(height: 1, indent: 52),
                  _buildMenuTile(
                    icon: Icons.dashboard_outlined,
                    title: 'Giám sát chấm công & Bảng công',
                    subtitle:
                        'Theo dõi trực tiếp nhân viên và bảng chấm công tháng',
                    color: AppColors.supervisor,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const LiveAttendanceDashboardPage(),
                        ),
                      );
                    },
                  ),
                  const Divider(height: 1, indent: 52),
                  _buildMenuTile(
                    icon: Icons.tune_outlined,
                    title: 'Cấu hình Ca làm việc & GPS',
                    subtitle: 'Thiết lập ca làm và tọa độ chi nhánh',
                    color: AppColors.chartTeal,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ShiftConfigPage(),
                        ),
                      );
                    },
                  ),
                ],
              ],
            ),

            // ==========================================
            // BLOCK 4: CẤU HÌNH & QUẢN TRỊ (Admin / Supervisor)
            // ==========================================
            if (user?.isAdmin == true || user?.isSupervisor == true) ...[
              _buildCardBlock(
                headerTitle: 'CẤU HÌNH & QUẢN TRỊ',
                headerIcon: Icons.admin_panel_settings_outlined,
                headerColor: AppColors.supervisor,
                children: [
                  if (user?.canManagePaymentConfig == true) ...[
                    _buildMenuTile(
                      icon: Icons.qr_code_2,
                      title: 'Cấu hình VietQR',
                      subtitle: 'Mẫu in hóa đơn K80/K58/A4 & VietQR',
                      color: AppColors.chartTeal,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const StorePaymentSettingsPage(),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, indent: 52),
                  ],
                  _buildMenuTile(
                    icon: Icons.manage_accounts_outlined,
                    title: l10n.accountManagement,
                    subtitle: 'Phân quyền & danh sách nhân viên',
                    color: AppColors.primary,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AccountManagementPage(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ],

            // ==========================================
            // BLOCK 5: HỆ THỐNG & TÀI KHOẢN
            // ==========================================
            _buildCardBlock(
              headerTitle: 'HỆ THỐNG',
              headerIcon: Icons.settings_outlined,
              headerColor: AppColors.grey600,
              children: [
                _buildMenuTile(
                  icon: Icons.lock_reset,
                  title: 'Đổi mật khẩu',
                  subtitle: 'Thay đổi mật khẩu đăng nhập tài khoản',
                  color: AppColors.primary,
                  onTap: () {
                    if (user?.username != null) {
                      _showChangePasswordDialog(context, ref, user!.username);
                    }
                  },
                ),
                const Divider(height: 1, indent: 52),
                _buildMenuTile(
                  icon: Icons.logout,
                  title: l10n.logout,
                  subtitle: 'Đăng xuất khỏi thiết bị này',
                  color: AppColors.danger,
                  isDanger: true,
                  onTap: () => _showLogoutDialog(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCardBlock({
    required String headerTitle,
    required IconData headerIcon,
    required Color headerColor,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(headerIcon, size: 16, color: headerColor),
              const SizedBox(width: 8),
              Text(
                headerTitle,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: AppColors.grey700,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildMenuTile({
    required IconData icon,
    required String title,
    String? subtitle,
    required Color color,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: isDanger
                    ? AppColors.danger.withOpacity(0.1)
                    : color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: isDanger ? AppColors.danger : color,
                size: 20,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color:
                          isDanger ? AppColors.danger : AppColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDanger
                            ? AppColors.danger.withOpacity(0.8)
                            : AppColors.grey600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: isDanger ? AppColors.danger : AppColors.grey400,
              size: 20,
            ),
          ],
        ),
      ),
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
                    await ref.read(authRemoteDataSourceProvider).updatePassword(
                          username,
                          oldPasswordController.text,
                          newPasswordController.text,
                        );
                    await ref
                        .read(authProvider.notifier)
                        .updateSavedPassword(newPasswordController.text);
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
              style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
              child: const Text('Lưu mật khẩu'),
            ),
          ],
        );
      },
    );
  }
}
