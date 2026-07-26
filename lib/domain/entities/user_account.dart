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

  Map<String, dynamic> toMap() {
    return {
      if (displayName != null) 'displayName': displayName,
      'role': role,
      'storeId': storeId,
    };
  }

  bool get isSupervisor => role == 'supervisor';

  bool get isAdmin => role == 'admin' || role == 'supervisor';

  bool get isStaff => role == 'nhanvien';
}
