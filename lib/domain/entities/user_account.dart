class UserAccount {
  final String username;
  final String? displayName;
  final String role; // 'supervisor', 'admin', or 'nhanvien'
  final String storeId;

  const UserAccount({
    required this.username,
    this.displayName,
    required this.role,
    required this.storeId,
  });

  String get name => (displayName != null && displayName!.isNotEmpty)
      ? displayName!
      : username;

  factory UserAccount.fromMap(String username, Map<dynamic, dynamic> map) {
    return UserAccount(
      username: username,
      displayName: map['displayName']?.toString(),
      role: map['role']?.toString() ?? 'nhanvien',
      storeId: map['storeId']?.toString() ?? '',
    );
  }

  factory UserAccount.fromJson(Map<String, dynamic> json) {
    final username = json['username']?.toString() ?? '';
    return UserAccount.fromMap(username, json);
  }

  Map<String, dynamic> toMap() {
    return {
      if (displayName != null) 'displayName': displayName,
      'role': role,
      'storeId': storeId,
    };
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      if (displayName != null) 'displayName': displayName,
      'role': role,
      'storeId': storeId,
    };
  }

  /// Vai trò:
  /// - Admin (Chủ cửa hàng / Quản trị viên tối cao): toàn quyền hệ thống, quản lý tất cả chi nhánh.
  /// - Supervisor (Cửa hàng trưởng / Giám sát chi nhánh): phụ trách 1 chi nhánh cụ thể.
  /// - Staff / Nhanvien: nhân viên thu ngân / bán hàng tại 1 chi nhánh.
  bool get isAdmin =>
      role.toLowerCase().trim() == 'admin' ||
      role.toLowerCase().trim() == 'owner';

  bool get isSupervisor {
    final r = role.toLowerCase().trim();
    return r == 'supervisor' || r == 'giamsat' || r == 'cuahangtruong';
  }

  bool get isStaff => !isAdmin && !isSupervisor;

  /// Phạm vi quản lý: Admin hoặc storeId rỗng/'all' quản lý toàn bộ chi nhánh
  bool get isAllStores => isAdmin || storeId == 'all' || storeId.trim().isEmpty;

  /// Quyền đổi chi nhánh xem báo cáo / bán hàng
  bool get canSwitchStore => isAdmin || isSupervisor;

  /// Quyền quản lý tài khoản người dùng và phân quyền (Chỉ Admin / Chủ shop)
  bool get canManageUsers => isAdmin;

  /// Quyền quản lý cấu hình ngân hàng VietQR
  bool get canManagePaymentConfig => isAdmin;

  /// Quyền quản lý sản phẩm (thêm / sửa / xóa / nhập hàng)
  bool get canManageProducts => isAdmin || isSupervisor;

  /// Quyền xóa hóa đơn (Chỉ Admin)
  bool get canDeleteInvoice => isAdmin;

  /// Quyền xóa khách hàng (Chỉ Admin)
  bool get canDeleteCustomer => isAdmin;

  /// Quyền xuất danh sách khách hàng (Admin & Supervisor)
  bool get canExportCustomers => isAdmin || isSupervisor;

  /// Quyền thay đổi chi nhánh nhập kho
  bool get canChangeImportStore => canSwitchStore;

  /// Quyền thay đổi chi nhánh nguồn chuyển kho
  bool get canChangeTransferSourceStore => canSwitchStore;

  /// Quyền sửa đơn giá và chiết khấu (Admin & Supervisor)
  bool get canEditPriceAndDiscount => isAdmin || isSupervisor;

  /// Quyền xem giá vốn và báo cáo lợi nhuận (Admin & Supervisor)
  bool get canViewCostPrice => isAdmin || isSupervisor;

  /// Quyền xem tổng nợ và sổ nợ
  bool get canViewDebtSummary => isAdmin || isSupervisor;

  /// Quyền xem tổng bán / doanh số khách hàng (Admin & Supervisor)
  bool get canViewTotalSales => isAdmin || isSupervisor;

  /// Quyền quản lý ca làm việc (Admin & Supervisor)
  bool get canManageShifts => isAdmin || isSupervisor;

  /// Quyền duyệt giải trình và điều chỉnh giờ công (Admin & Supervisor)
  bool get canAdjustAttendance => isAdmin || isSupervisor;

  /// Chỉ nhân viên mới là đối tượng phải điểm danh chấm công vào / ra
  bool get requiresAttendance => isStaff;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserAccount &&
          runtimeType == other.runtimeType &&
          username == other.username &&
          displayName == other.displayName &&
          role == other.role &&
          storeId == other.storeId;

  @override
  int get hashCode =>
      username.hashCode ^
      displayName.hashCode ^
      role.hashCode ^
      storeId.hashCode;
}
