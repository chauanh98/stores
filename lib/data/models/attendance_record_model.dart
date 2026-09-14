import '../../domain/attendance/attendance_record.dart';

class AttendanceRecordModel {
  final String id;
  final String userId;
  final String userName;
  final String storeId;
  final String shiftId;
  final String shiftName;
  final String date; // YYYY-MM-DD
  final String checkInTime; // ISO8601
  final String? checkOutTime; // ISO8601
  final String status;
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
  final String? createdAt;
  final String? updatedAt;

  const AttendanceRecordModel({
    required this.id,
    required this.userId,
    required this.userName,
    required this.storeId,
    required this.shiftId,
    required this.shiftName,
    required this.date,
    required this.checkInTime,
    this.checkOutTime,
    this.status = 'on_time',
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

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'userId': userId,
      'userName': userName,
      'storeId': storeId,
      'shiftId': shiftId,
      'shiftName': shiftName,
      'date': date,
      'checkInTime': checkInTime,
      'checkOutTime': checkOutTime,
      'status': status,
      'lateMinutes': lateMinutes,
      'earlyLeaveMinutes': earlyLeaveMinutes,
      'overtimeMinutes': overtimeMinutes,
      'checkInGpsLat': checkInGpsLat,
      'checkInGpsLng': checkInGpsLng,
      'isGpsValid': isGpsValid,
      'explanationReason': explanationReason,
      'checkOutGpsLat': checkOutGpsLat,
      'checkOutGpsLng': checkOutGpsLng,
      'isCheckOutGpsValid': isCheckOutGpsValid,
      'totalWorkHours': totalWorkHours,
      'isAdjusted': isAdjusted,
      'adjustmentId': adjustmentId,
      'createdAt': createdAt,
      'updatedAt': updatedAt,
    };
  }

  factory AttendanceRecordModel.fromMap(Map<dynamic, dynamic> map, {String? id}) {
    return AttendanceRecordModel(
      id: id ?? map['id']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      userName: map['userName']?.toString() ?? '',
      storeId: map['storeId']?.toString() ?? '',
      shiftId: map['shiftId']?.toString() ?? '',
      shiftName: map['shiftName']?.toString() ?? '',
      date: map['date']?.toString() ?? '',
      checkInTime: map['checkInTime']?.toString() ?? '',
      checkOutTime: map['checkOutTime']?.toString(),
      status: map['status']?.toString() ?? 'on_time',
      lateMinutes: (map['lateMinutes'] as num?)?.toInt() ?? 0,
      earlyLeaveMinutes: (map['earlyLeaveMinutes'] as num?)?.toInt() ?? 0,
      overtimeMinutes: (map['overtimeMinutes'] as num?)?.toInt() ?? 0,
      checkInGpsLat: (map['checkInGpsLat'] as num?)?.toDouble() ?? 0.0,
      checkInGpsLng: (map['checkInGpsLng'] as num?)?.toDouble() ?? 0.0,
      isGpsValid: map['isGpsValid'] == null ? true : (map['isGpsValid'] as bool),
      explanationReason: map['explanationReason']?.toString(),
      checkOutGpsLat: (map['checkOutGpsLat'] as num?)?.toDouble(),
      checkOutGpsLng: (map['checkOutGpsLng'] as num?)?.toDouble(),
      isCheckOutGpsValid: map['isCheckOutGpsValid'] as bool?,
      totalWorkHours: (map['totalWorkHours'] as num?)?.toDouble() ?? 0.0,
      isAdjusted: map['isAdjusted'] == null ? false : (map['isAdjusted'] as bool),
      adjustmentId: map['adjustmentId']?.toString(),
      createdAt: map['createdAt']?.toString(),
      updatedAt: map['updatedAt']?.toString(),
    );
  }

  AttendanceRecord toDomain() {
    DateTime parsedDate;
    try {
      parsedDate = DateTime.parse(date);
    } catch (_) {
      parsedDate = DateTime.now();
    }

    DateTime parsedCheckIn;
    try {
      parsedCheckIn = DateTime.parse(checkInTime);
    } catch (_) {
      parsedCheckIn = DateTime.now();
    }

    DateTime? parsedCheckOut;
    if (checkOutTime != null) {
      try {
        parsedCheckOut = DateTime.parse(checkOutTime!);
      } catch (_) {}
    }

    DateTime? parsedCreatedAt;
    if (createdAt != null) {
      try {
        parsedCreatedAt = DateTime.parse(createdAt!);
      } catch (_) {}
    }

    DateTime? parsedUpdatedAt;
    if (updatedAt != null) {
      try {
        parsedUpdatedAt = DateTime.parse(updatedAt!);
      } catch (_) {}
    }

    return AttendanceRecord(
      id: id,
      userId: userId,
      userName: userName,
      storeId: storeId,
      shiftId: shiftId,
      shiftName: shiftName,
      date: parsedDate,
      checkInTime: parsedCheckIn,
      checkOutTime: parsedCheckOut,
      status: AttendanceStatus.fromString(status),
      lateMinutes: lateMinutes,
      earlyLeaveMinutes: earlyLeaveMinutes,
      overtimeMinutes: overtimeMinutes,
      checkInGpsLat: checkInGpsLat,
      checkInGpsLng: checkInGpsLng,
      isGpsValid: isGpsValid,
      explanationReason: explanationReason,
      checkOutGpsLat: checkOutGpsLat,
      checkOutGpsLng: checkOutGpsLng,
      isCheckOutGpsValid: isCheckOutGpsValid,
      totalWorkHours: totalWorkHours,
      isAdjusted: isAdjusted,
      adjustmentId: adjustmentId,
      createdAt: parsedCreatedAt,
      updatedAt: parsedUpdatedAt,
    );
  }

  factory AttendanceRecordModel.fromDomain(AttendanceRecord record) {
    return AttendanceRecordModel(
      id: record.id,
      userId: record.userId,
      userName: record.userName,
      storeId: record.storeId,
      shiftId: record.shiftId,
      shiftName: record.shiftName,
      date: '${record.date.year.toString().padLeft(4, '0')}-${record.date.month.toString().padLeft(2, '0')}-${record.date.day.toString().padLeft(2, '0')}',
      checkInTime: record.checkInTime.toIso8601String(),
      checkOutTime: record.checkOutTime?.toIso8601String(),
      status: record.status.value,
      lateMinutes: record.lateMinutes,
      earlyLeaveMinutes: record.earlyLeaveMinutes,
      overtimeMinutes: record.overtimeMinutes,
      checkInGpsLat: record.checkInGpsLat,
      checkInGpsLng: record.checkInGpsLng,
      isGpsValid: record.isGpsValid,
      explanationReason: record.explanationReason,
      checkOutGpsLat: record.checkOutGpsLat,
      checkOutGpsLng: record.checkOutGpsLng,
      isCheckOutGpsValid: record.isCheckOutGpsValid,
      totalWorkHours: record.totalWorkHours,
      isAdjusted: record.isAdjusted,
      adjustmentId: record.adjustmentId,
      createdAt: record.createdAt?.toIso8601String(),
      updatedAt: record.updatedAt?.toIso8601String(),
    );
  }
}
