class Supplier {
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

  const Supplier({
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

  bool get isActive => status == 'active' || status == '1';
  bool get hasDebt => currentDebt > 0;

  Supplier copyWith({
    String? id,
    String? code,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? taxCode,
    double? totalPurchase,
    double? currentDebt,
    String? note,
    String? status,
    String? branch,
    String? createdAt,
    String? createdBy,
  }) {
    return Supplier(
      id: id ?? this.id,
      code: code ?? this.code,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      taxCode: taxCode ?? this.taxCode,
      totalPurchase: totalPurchase ?? this.totalPurchase,
      currentDebt: currentDebt ?? this.currentDebt,
      note: note ?? this.note,
      status: status ?? this.status,
      branch: branch ?? this.branch,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Supplier &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          code == other.code &&
          name == other.name &&
          phone == other.phone &&
          email == other.email &&
          address == other.address &&
          taxCode == other.taxCode &&
          totalPurchase == other.totalPurchase &&
          currentDebt == other.currentDebt &&
          note == other.note &&
          status == other.status &&
          branch == other.branch &&
          createdAt == other.createdAt &&
          createdBy == other.createdBy;

  @override
  int get hashCode =>
      id.hashCode ^
      code.hashCode ^
      name.hashCode ^
      phone.hashCode ^
      email.hashCode ^
      address.hashCode ^
      taxCode.hashCode ^
      totalPurchase.hashCode ^
      currentDebt.hashCode ^
      note.hashCode ^
      status.hashCode ^
      branch.hashCode ^
      createdAt.hashCode ^
      createdBy.hashCode;

  @override
  String toString() {
    return 'Supplier(id: $id, code: $code, name: $name, phone: $phone, currentDebt: $currentDebt, totalPurchase: $totalPurchase)';
  }
}
