import 'package:stores/domain/entities/purchase.dart';

class Customer {
  final String id;
  final String name;
  final String phone;
  final String email;
  final String address;
  final List<Purchase> purchases;

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    required this.email,
    required this.address,
    required this.purchases,
  });
}