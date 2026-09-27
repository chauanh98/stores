import '../../domain/attendance/attendance_adjustment.dart';

class AttendanceAdjustmentModel {
  final String id;
  final String attendanceId;
  final String userId;
  final String userName;
  final String storeId;
  final String requestedCheckIn; // ISO8601
  final String requestedCheckOut; // ISO8601
  final String reason;
  final String status;
  final String? reviewedBy;
  final String? reviewedAt;
  final String? reviewNote;
  final String? submittedAt;

  const AttendanceAdjustmentModel({
    required this.id,
    required this.attendanceId,
    required this.userId,
    required this.userName,
    required this.storeId,
    required this.requestedCheckIn,
    required this.requestedCheckOut,
    required this.reason,
    this.status = 'pending',
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    this.submittedAt,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'attendanceId': attendanceId,
      'userId': userId,
      'userName': userName,
      'storeId': storeId,
      'requestedCheckIn': requestedCheckIn,
      'requestedCheckOut': requestedCheckOut,
      'reason': reason,
      'status': status,
      'reviewedBy': reviewedBy,
      'reviewedAt': reviewedAt,
      'reviewNote': reviewNote,
      'submittedAt': submittedAt,
    };
  }

  factory AttendanceAdjustmentModel.fromMap(Map<dynamic, dynamic> map,
      {String? id}) {
    return AttendanceAdjustmentModel(
      id: id ?? map['id']?.toString() ?? '',
      attendanceId: map['attendanceId']?.toString() ?? '',
      userId: map['userId']?.toString() ?? '',
      userName: map['userName']?.toString() ?? '',
      storeId: map['storeId']?.toString() ?? '',
      requestedCheckIn: map['requestedCheckIn']?.toString() ?? '',
      requestedCheckOut: map['requestedCheckOut']?.toString() ?? '',
      reason: map['reason']?.toString() ?? '',
      status: map['status']?.toString() ?? 'pending',
      reviewedBy: map['reviewedBy']?.toString(),
      reviewedAt: map['reviewedAt']?.toString(),
      reviewNote: map['reviewNote']?.toString(),
      submittedAt: map['submittedAt']?.toString(),
    );
  }

  AttendanceAdjustment toDomain() {
    DateTime parsedCheckIn;
    try {
      parsedCheckIn = DateTime.parse(requestedCheckIn);
    } catch (_) {
      parsedCheckIn = DateTime.now();
    }

    DateTime parsedCheckOut;
    try {
      parsedCheckOut = DateTime.parse(requestedCheckOut);
    } catch (_) {
      parsedCheckOut = DateTime.now();
    }

    DateTime? parsedReviewedAt;
    if (reviewedAt != null) {
      try {
        parsedReviewedAt = DateTime.parse(reviewedAt!);
      } catch (_) {}
    }

    DateTime? parsedSubmittedAt;
    if (submittedAt != null) {
      try {
        parsedSubmittedAt = DateTime.parse(submittedAt!);
      } catch (_) {}
    }

    return AttendanceAdjustment(
      id: id,
      attendanceId: attendanceId,
      userId: userId,
      userName: userName,
      storeId: storeId,
      requestedCheckIn: parsedCheckIn,
      requestedCheckOut: parsedCheckOut,
      reason: reason,
      status: AdjustmentStatus.fromString(status),
      reviewedBy: reviewedBy,
      reviewedAt: parsedReviewedAt,
      reviewNote: reviewNote,
      submittedAt: parsedSubmittedAt,
    );
  }

  factory AttendanceAdjustmentModel.fromDomain(AttendanceAdjustment adj) {
    return AttendanceAdjustmentModel(
      id: adj.id,
      attendanceId: adj.attendanceId,
      userId: adj.userId,
      userName: adj.userName,
      storeId: adj.storeId,
      requestedCheckIn: adj.requestedCheckIn.toIso8601String(),
      requestedCheckOut: adj.requestedCheckOut.toIso8601String(),
      reason: adj.reason,
      status: adj.status.value,
      reviewedBy: adj.reviewedBy,
      reviewedAt: adj.reviewedAt?.toIso8601String(),
      reviewNote: adj.reviewNote,
      submittedAt: adj.submittedAt?.toIso8601String(),
    );
  }
}
