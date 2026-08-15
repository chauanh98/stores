class StorePaymentConfig {
  final String storeId;
  final String storeName;
  final String address;
  final String phone;
  final String bankName;
  final String bankId;
  final String accountNo;
  final String accountName;
  final String footerNote;

  const StorePaymentConfig({
    required this.storeId,
    this.storeName = 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG',
    this.address = 'Chợ Cờ Đỏ, Xã Cờ Đỏ, Cần Thơ',
    this.phone = '0917.865 300 - 0939.865 300',
    this.bankName = 'VIETINBANK',
    this.bankId = 'vietinbank',
    this.accountNo = '0917865300',
    this.accountName = 'Huỳnh Lê Khánh Đăng',
    this.footerNote = 'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG - ĐÚNG CHẤT LIỆU GỖ',
  });

  Map<String, dynamic> toMap() {
    return {
      'storeId': storeId,
      'storeName': storeName,
      'address': address,
      'phone': phone,
      'bankName': bankName,
      'bankId': bankId,
      'accountNo': accountNo,
      'accountName': accountName,
      'footerNote': footerNote,
    };
  }

  factory StorePaymentConfig.fromMap(String storeId, Map<dynamic, dynamic>? map) {
    if (map == null) return StorePaymentConfig(storeId: storeId);
    return StorePaymentConfig(
      storeId: storeId,
      storeName: map['storeName']?.toString() ?? 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG',
      address: map['address']?.toString() ?? 'Chợ Cờ Đỏ, Xã Cờ Đỏ, Cần Thơ',
      phone: map['phone']?.toString() ?? '0917.865 300 - 0939.865 300',
      bankName: map['bankName']?.toString() ?? 'VIETINBANK',
      bankId: map['bankId']?.toString() ?? 'vietinbank',
      accountNo: map['accountNo']?.toString() ?? '0917865300',
      accountName: map['accountName']?.toString() ?? 'Huỳnh Lê Khánh Đăng',
      footerNote: map['footerNote']?.toString() ??
          'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG - ĐÚNG CHẤT LIỆU GỖ',
    );
  }

  StorePaymentConfig copyWith({
    String? storeId,
    String? storeName,
    String? address,
    String? phone,
    String? bankName,
    String? bankId,
    String? accountNo,
    String? accountName,
    String? footerNote,
  }) {
    return StorePaymentConfig(
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      bankName: bankName ?? this.bankName,
      bankId: bankId ?? this.bankId,
      accountNo: accountNo ?? this.accountNo,
      accountName: accountName ?? this.accountName,
      footerNote: footerNote ?? this.footerNote,
    );
  }
}
