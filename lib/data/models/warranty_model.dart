class WarrantyModel {
  final int months;
  final DateTime expireDate;

  const WarrantyModel({required this.months, required this.expireDate});

  Map<String, dynamic> toMap() => {
    'months': months,
    'expireDate': expireDate.toIso8601String(),
  };

  factory WarrantyModel.fromMap(Map<dynamic, dynamic> map) => WarrantyModel(
    months: map['months'] as int,
    expireDate: DateTime.parse(map['expireDate'] as String),
  );
}