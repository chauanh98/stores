import '../../domain/entities/supplier.dart';

class SupplierModel {
  final String id;
  final String code;
  final String name;
  final String phone;
  final String email;
  final String address;
  final String? taxCode;
  final double totalPurchase;
  final double currentDebt;
  final String? note;
  final String status;
  final String? branch;
  final String? createdAt;
  final String? createdBy;

  const SupplierModel({
    required this.id,
    required this.code,
    required this.name,
    this.phone = '',
    this.email = '',
    this.address = '',
    this.taxCode,
    this.totalPurchase = 0.0,
    this.currentDebt = 0.0,
    this.note,
    this.status = 'active',
    this.branch,
    this.createdAt,
    this.createdBy,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'code': code,
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'taxCode': taxCode,
      'totalPurchase': totalPurchase,
      'currentDebt': currentDebt,
      'note': note,
      'status': status,
      'branch': branch,
      'createdAt': createdAt,
      'createdBy': createdBy,
    };
  }

  factory SupplierModel.fromMap(Map<dynamic, dynamic> map) {
    return SupplierModel(
      id: map['id']?.toString() ?? '',
      code: map['code']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      phone: map['phone']?.toString() ?? '',
      email: map['email']?.toString() ?? '',
      address: map['address']?.toString() ?? '',
      taxCode: map['taxCode']?.toString(),
      totalPurchase: (map['totalPurchase'] as num?)?.toDouble() ?? 0.0,
      currentDebt: (map['currentDebt'] as num?)?.toDouble() ?? 0.0,
      note: map['note']?.toString(),
      status: map['status']?.toString() ?? 'active',
      branch: map['branch']?.toString(),
      createdAt: map['createdAt']?.toString(),
      createdBy: map['createdBy']?.toString(),
    );
  }

  Supplier toDomain() {
    return Supplier(
      id: id,
      code: code.isNotEmpty ? code : id,
      name: name,
      phone: phone,
      email: email,
      address: address,
      taxCode: taxCode,
      totalPurchase: totalPurchase,
      currentDebt: currentDebt,
      note: note,
      status: status,
      branch: branch,
      createdAt: createdAt,
      createdBy: createdBy,
    );
  }

  factory SupplierModel.fromDomain(Supplier supplier) {
    return SupplierModel(
      id: supplier.id,
      code: supplier.code,
      name: supplier.name,
      phone: supplier.phone,
      email: supplier.email,
      address: supplier.address,
      taxCode: supplier.taxCode,
      totalPurchase: supplier.totalPurchase,
      currentDebt: supplier.currentDebt,
      note: supplier.note,
      status: supplier.status,
      branch: supplier.branch,
      createdAt: supplier.createdAt,
      createdBy: supplier.createdBy,
    );
  }
}
