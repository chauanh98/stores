import 'package:stores/domain/entities/warranty.dart';

class Purchase {
  final String productId;
  final int quantity;
  final DateTime purchaseDate;
  final Warranty warranty;

  const Purchase({
    required this.productId,
    required this.quantity,
    required this.purchaseDate,
    required this.warranty,
  });
}