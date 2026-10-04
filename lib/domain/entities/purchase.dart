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

  Purchase copyWith({
    String? productId,
    int? quantity,
    DateTime? purchaseDate,
    Warranty? warranty,
  }) {
    return Purchase(
      productId: productId ?? this.productId,
      quantity: quantity ?? this.quantity,
      purchaseDate: purchaseDate ?? this.purchaseDate,
      warranty: warranty ?? this.warranty,
    );
  }
}
