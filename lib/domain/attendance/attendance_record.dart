/// Status of staff attendance.
enum AttendanceStatus {
  onTime('on_time', 'Đúng giờ'),
  late('late', 'Đi muộn'),
  earlyLeave('early_leave', 'Về sớm'),
  overtime('overtime', 'Tăng ca');

  final String value;
  final String label;

  const AttendanceStatus(this.value, this.label);

  static AttendanceStatus fromString(String? value) {
    if (value == null) return AttendanceStatus.onTime;
    final normalized = value.toLowerCase().trim().replaceAll('-', '_');
    return AttendanceStatus.values.firstWhere(
      (e) =>
          e.value == normalized ||
          e.name.toLowerCase() == normalized.replaceAll('_', ''),
      orElse: () => AttendanceStatus.onTime,
    );
  }
}

/// Domain entity representing a staff attendance check-in/check-out record.
class AttendanceRecord {
  final String id;
  final String userId;
  final String userName;
  final String storeId;
  final String shiftId;
  final String shiftName;
  final DateTime date;
  final DateTime checkInTime;
  final DateTime? checkOutTime;
  final AttendanceStatus status;
  final int lateMinutes;
  final int earlyLeaveMinutes;
  final int overtimeMinutes;
  final double checkInGpsLat;
  final double checkInGpsLng;
  final bool isGpsValid;
  final String? explanationReason;
  final double? checkOutGpsLat;
  final double? checkOutGpsLng;
  final bool? isCheckOutGpsValid;
  final double totalWorkHours;
  final bool isAdjusted;
  final String? adjustmentId;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const AttendanceRecord({
    required this.id,
    required this.userId,
    required this.userName,
    required this.storeId,
    required this.shiftId,
    required this.shiftName,
    required this.date,
    required this.checkInTime,
    this.checkOutTime,
    this.status = AttendanceStatus.onTime,
    this.lateMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.overtimeMinutes = 0,
    required this.checkInGpsLat,
    required this.checkInGpsLng,
    required this.isGpsValid,
    this.explanationReason,
    this.checkOutGpsLat,
    this.checkOutGpsLng,
    this.isCheckOutGpsValid,
    this.totalWorkHours = 0.0,
    this.isAdjusted = false,
    this.adjustmentId,
    this.createdAt,
    this.updatedAt,
  });

  /// Alias getters for interface contract compatibility
  double get checkInLat => checkInGpsLat;
  double get checkInLng => checkInGpsLng;

  /// Whether the employee is currently active on this shift (checked in, not yet checked out)
  bool get isWorking => checkOutTime == null;

  /// Helper to calculate decimal work hours between checkIn and checkOut
  static double calculateWorkHours(DateTime checkIn, DateTime? checkOut) {
    if (checkOut == null) return 0.0;
    final diff = checkOut.difference(checkIn);
    if (diff.isNegative) return 0.0;
    final hours = diff.inMinutes / 60.0;
    return double.parse(hours.toStringAsFixed(2));
  }

  AttendanceRecord copyWith({
    String? id,
    String? userId,
    String? userName,
    String? storeId,
    String? shiftId,
    String? shiftName,
    DateTime? date,
    DateTime? checkInTime,
    DateTime? checkOutTime,
    AttendanceStatus? status,
    int? lateMinutes,
    int? earlyLeaveMinutes,
    int? overtimeMinutes,
    double? checkInGpsLat,
    double? checkInGpsLng,
    bool? isGpsValid,
    String? explanationReason,
    double? checkOutGpsLat,
    double? checkOutGpsLng,
    bool? isCheckOutGpsValid,
    double? totalWorkHours,
    bool? isAdjusted,
    String? adjustmentId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      storeId: storeId ?? this.storeId,
      shiftId: shiftId ?? this.shiftId,
      shiftName: shiftName ?? this.shiftName,
      date: date ?? this.date,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      status: status ?? this.status,
      lateMinutes: lateMinutes ?? this.lateMinutes,
      earlyLeaveMinutes: earlyLeaveMinutes ?? this.earlyLeaveMinutes,
      overtimeMinutes: overtimeMinutes ?? this.overtimeMinutes,
      checkInGpsLat: checkInGpsLat ?? this.checkInGpsLat,
      checkInGpsLng: checkInGpsLng ?? this.checkInGpsLng,
      isGpsValid: isGpsValid ?? this.isGpsValid,
      explanationReason: explanationReason ?? this.explanationReason,
      checkOutGpsLat: checkOutGpsLat ?? this.checkOutGpsLat,
      checkOutGpsLng: checkOutGpsLng ?? this.checkOutGpsLng,
      isCheckOutGpsValid: isCheckOutGpsValid ?? this.isCheckOutGpsValid,
      totalWorkHours: totalWorkHours ?? this.totalWorkHours,
      isAdjusted: isAdjusted ?? this.isAdjusted,
      adjustmentId: adjustmentId ?? this.adjustmentId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttendanceRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          userId == other.userId &&
          storeId == other.storeId &&
          shiftId == other.shiftId &&
          checkInTime == other.checkInTime &&
          checkOutTime == other.checkOutTime &&
          status == other.status &&
          isAdjusted == other.isAdjusted;

  @override
  int get hashCode =>
      id.hashCode ^
      userId.hashCode ^
      storeId.hashCode ^
      shiftId.hashCode ^
      checkInTime.hashCode ^
      (checkOutTime?.hashCode ?? 0) ^
      status.hashCode ^
      isAdjusted.hashCode;
}
