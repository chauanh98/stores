import 'package:stores/data/models/purchase_model.dart';

class CustomerModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final List<PurchaseModel> purchases;

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

  const CustomerModel({
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

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'phone': phone,
        'email': email,
        'address': address,
        'purchases': purchases.map((e) => e.toMap()).toList(),
        'type': type,
        'branch': branch,
        'deliveryArea': deliveryArea,
        'ward': ward,
        'company': company,
        'taxCode': taxCode,
        'identityCard': identityCard,
        'dob': dob,
        'gender': gender,
        'facebook': facebook,
        'group': group,
        'notes': notes,
        'createdBy': createdBy,
        'createdAt': createdAt,
        'lastTransactionDate': lastTransactionDate,
        'currentDebt': currentDebt,
        'totalSales': totalSales,
        'netSales': netSales,
        'status': status,
      };

  factory CustomerModel.fromMap(Map<dynamic, dynamic> map) => CustomerModel(
        id: map['id'] as String? ?? '',
        name: map['name'] as String? ?? '',
        phone: map['phone'] as String? ?? '',
        email: map['email'] as String? ?? '',
        address: map['address'] as String? ?? '',
        purchases: () {
          final raw = map['purchases'];
          if (raw is List) {
            return raw
                .where((e) => e != null)
                .map((e) => PurchaseModel.fromMap(e as Map))
                .toList();
          }
          if (raw is Map) {
            return raw.values
                .where((e) => e != null)
                .map((e) => PurchaseModel.fromMap(e as Map))
                .toList();
          }
          return <PurchaseModel>[];
        }(),
        type: map['type'] as String?,
        branch: map['branch'] as String?,
        deliveryArea: map['deliveryArea'] as String?,
        ward: map['ward'] as String?,
        company: map['company'] as String?,
        taxCode: map['taxCode'] as String?,
        identityCard: map['identityCard'] as String?,
        dob: map['dob'] as String?,
        gender: map['gender'] as String?,
        facebook: map['facebook'] as String?,
        group: map['group'] as String?,
        notes: map['notes'] as String?,
        createdBy: map['createdBy'] as String?,
        createdAt: map['createdAt'] as String?,
        lastTransactionDate: map['lastTransactionDate'] as String?,
        currentDebt: map['currentDebt'] != null
            ? (map['currentDebt'] as num).toDouble()
            : null,
        totalSales: map['totalSales'] != null
            ? (map['totalSales'] as num).toDouble()
            : null,
        netSales: map['netSales'] != null
            ? (map['netSales'] as num).toDouble()
            : null,
        status: map['status']?.toString(),
      );
}
