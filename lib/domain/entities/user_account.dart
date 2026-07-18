class UserAccount {
  final String username;
  final String role; // 'admin' or 'nhanvien'
  final String storeId;

  const UserAccount({
    required this.username,
    required this.role,
    required this.storeId,
  });

  factory UserAccount.fromMap(String username, Map<dynamic, dynamic> map) {
    return UserAccount(
      username: username,
      role: map['role']?.toString() ?? 'nhanvien',
      storeId: map['storeId']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'role': role,
      'storeId': storeId,
    };
  }

  bool get isAdmin => role == 'admin';
}
