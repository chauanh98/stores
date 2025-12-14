import 'package:stores/data/models/purchase_model.dart';

class CustomerModel {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final List<PurchaseModel> purchases;

  const CustomerModel({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.purchases,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'purchases': purchases.map((e) => e.toMap()).toList(),
  };

  factory CustomerModel.fromMap(Map<dynamic, dynamic> map) => CustomerModel(
    id: map['id'] as String,
    name: map['name'] as String,
    phone: map['phone'] as String,
    email: map['email'] as String,
    address: map['address'] as String,
    purchases: (map['purchases'] as List? ?? [])
        .map((e) => PurchaseModel.fromMap(e as Map))
        .toList(),
  );
}