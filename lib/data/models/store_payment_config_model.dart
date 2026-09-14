import '../../domain/entities/store_payment_config.dart';

class StorePaymentConfigModel {
  final String storeId;
  final String storeName;
  final String address;
  final String phone;
  final String bankName;
  final String bankId;
  final String accountNo;
  final String accountName;
  final String footerNote;
  final String paperSize;
  final bool showVietQR;

  const StorePaymentConfigModel({
    required this.storeId,
    this.storeName = 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG',
    this.address = 'Chợ Cờ Đỏ, Xã Cờ Đỏ, Cần Thơ',
    this.phone = '0917.865 300 - 0939.865 300',
    this.bankName = 'VIETINBANK',
    this.bankId = 'vietinbank',
    this.accountNo = '0917865300',
    this.accountName = 'Huỳnh Lê Khánh Đăng',
    this.footerNote = 'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG - ĐÚNG CHẤT LIỆU GỖ',
    this.paperSize = 'k80',
    this.showVietQR = true,
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
      'paperSize': paperSize,
      'showVietQR': showVietQR,
    };
  }

  factory StorePaymentConfigModel.fromMap(Map<dynamic, dynamic> map, [String? fallbackStoreId]) {
    return StorePaymentConfigModel(
      storeId: map['storeId']?.toString() ?? fallbackStoreId ?? '',
      storeName: map['storeName']?.toString() ?? 'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG',
      address: map['address']?.toString() ?? 'Chợ Cờ Đỏ, Xã Cờ Đỏ, Cần Thơ',
      phone: map['phone']?.toString() ?? '0917.865 300 - 0939.865 300',
      bankName: map['bankName']?.toString() ?? 'VIETINBANK',
      bankId: map['bankId']?.toString() ?? 'vietinbank',
      accountNo: map['accountNo']?.toString() ?? '0917865300',
      accountName: map['accountName']?.toString() ?? 'Huỳnh Lê Khánh Đăng',
      footerNote: map['footerNote']?.toString() ??
          'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG - ĐÚNG CHẤT LIỆU GỖ',
      paperSize: map['paperSize']?.toString() ?? 'k80',
      showVietQR: map['showVietQR'] is bool
          ? map['showVietQR'] as bool
          : (map['showVietQR'] == null ||
              map['showVietQR'].toString().toLowerCase() == 'true'),
    );
  }

  StorePaymentConfig toDomain() {
    return StorePaymentConfig(
      storeId: storeId,
      storeName: storeName,
      address: address,
      phone: phone,
      bankName: bankName,
      bankId: bankId,
      accountNo: accountNo,
      accountName: accountName,
      footerNote: footerNote,
      paperSize: paperSize,
      showVietQR: showVietQR,
    );
  }

  factory StorePaymentConfigModel.fromDomain(StorePaymentConfig config) {
    return StorePaymentConfigModel(
      storeId: config.storeId,
      storeName: config.storeName,
      address: config.address,
      phone: config.phone,
      bankName: config.bankName,
      bankId: config.bankId,
      accountNo: config.accountNo,
      accountName: config.accountName,
      footerNote: config.footerNote,
      paperSize: config.paperSize,
      showVietQR: config.showVietQR,
    );
  }

  StorePaymentConfigModel copyWith({
    String? storeId,
    String? storeName,
    String? address,
    String? phone,
    String? bankName,
    String? bankId,
    String? accountNo,
    String? accountName,
    String? footerNote,
    String? paperSize,
    bool? showVietQR,
  }) {
    return StorePaymentConfigModel(
      storeId: storeId ?? this.storeId,
      storeName: storeName ?? this.storeName,
      address: address ?? this.address,
      phone: phone ?? this.phone,
      bankName: bankName ?? this.bankName,
      bankId: bankId ?? this.bankId,
      accountNo: accountNo ?? this.accountNo,
      accountName: accountName ?? this.accountName,
      footerNote: footerNote ?? this.footerNote,
      paperSize: paperSize ?? this.paperSize,
      showVietQR: showVietQR ?? this.showVietQR,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StorePaymentConfigModel &&
          runtimeType == other.runtimeType &&
          storeId == other.storeId &&
          storeName == other.storeName &&
          address == other.address &&
          phone == other.phone &&
          bankName == other.bankName &&
          bankId == other.bankId &&
          accountNo == other.accountNo &&
          accountName == other.accountName &&
          footerNote == other.footerNote &&
          paperSize == other.paperSize &&
          showVietQR == other.showVietQR;

  @override
  int get hashCode => Object.hash(
        storeId,
        storeName,
        address,
        phone,
        bankName,
        bankId,
        accountNo,
        accountName,
        footerNote,
        paperSize,
        showVietQR,
      );
}
