import 'package:stores/data/models/warranty_model.dart';

class PurchaseModel {
  final String productId;
  final int quantity;
  final DateTime purchaseDate;
  final WarrantyModel warranty;

  const PurchaseModel({
    required this.productId,
    required this.quantity,
    required this.purchaseDate,
    required this.warranty,
  });

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'quantity': quantity,
        'purchaseDate': purchaseDate.toIso8601String(),
        'warranty': warranty.toMap(),
      };

  factory PurchaseModel.fromMap(Map<dynamic, dynamic> map) => PurchaseModel(
        productId: map['productId'] as String,
        quantity: map['quantity'] as int,
        purchaseDate: DateTime.parse(map['purchaseDate'] as String),
        warranty: WarrantyModel.fromMap(map['warranty'] as Map),
      );
}
