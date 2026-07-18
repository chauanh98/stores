import 'package:stores/domain/entities/purchase.dart';

class Customer {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final List<Purchase> purchases;

  // New fields from Excel
  final String? type;
  final String? branch;
  final String? deliveryArea;
  final String? ward;
  final String? company;
  final String? taxCode;
  final String? identityCard;
  final String? dob;
  final String? gender;
  final String? facebook;
  final String? group;
  final String? notes;
  final String? createdBy;
  final String? createdAt;
  final String? lastTransactionDate;
  final double? currentDebt;
  final double? totalSales;
  final double? netSales;
  final String? status;

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.purchases,
    this.type,
    this.branch,
    this.deliveryArea,
    this.ward,
    this.company,
    this.taxCode,
    this.identityCard,
    this.dob,
    this.gender,
    this.facebook,
    this.group,
    this.notes,
    this.createdBy,
    this.createdAt,
    this.lastTransactionDate,
    this.currentDebt,
    this.totalSales,
    this.netSales,
    this.status,
  });

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    List<Purchase>? purchases,
    String? type,
    String? branch,
    String? deliveryArea,
    String? ward,
    String? company,
    String? taxCode,
    String? identityCard,
    String? dob,
    String? gender,
    String? facebook,
    String? group,
    String? notes,
    String? createdBy,
    String? createdAt,
    String? lastTransactionDate,
    double? currentDebt,
    double? totalSales,
    double? netSales,
    String? status,
  }) =>
      Customer(
        id: id ?? this.id,
        name: name ?? this.name,
        phone: phone ?? this.phone,
        email: email ?? this.email,
        address: address ?? this.address,
        purchases: purchases ?? this.purchases,
        type: type ?? this.type,
        branch: branch ?? this.branch,
        deliveryArea: deliveryArea ?? this.deliveryArea,
        ward: ward ?? this.ward,
        company: company ?? this.company,
        taxCode: taxCode ?? this.taxCode,
        identityCard: identityCard ?? this.identityCard,
        dob: dob ?? this.dob,
        gender: gender ?? this.gender,
        facebook: facebook ?? this.facebook,
        group: group ?? this.group,
        notes: notes ?? this.notes,
        createdBy: createdBy ?? this.createdBy,
        createdAt: createdAt ?? this.createdAt,
        lastTransactionDate: lastTransactionDate ?? this.lastTransactionDate,
        currentDebt: currentDebt ?? this.currentDebt,
        totalSales: totalSales ?? this.totalSales,
        netSales: netSales ?? this.netSales,
        status: status ?? this.status,
      );
}
