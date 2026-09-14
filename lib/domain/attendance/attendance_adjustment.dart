/// Status of attendance adjustment request.
enum AdjustmentStatus {
  pending('pending', 'Chờ duyệt'),
  approved('approved', 'Đã duyệt'),
  rejected('rejected', 'Từ chối');

  final String value;
  final String label;

  const AdjustmentStatus(this.value, this.label);

  static AdjustmentStatus fromString(String? value) {
    if (value == null) return AdjustmentStatus.pending;
    final normalized = value.toLowerCase().trim();
    return AdjustmentStatus.values.firstWhere(
      (e) => e.value == normalized || e.name == normalized,
      orElse: () => AdjustmentStatus.pending,
    );
  }
}

/// Domain entity representing a staff request to adjust check-in/check-out times.
class AttendanceAdjustment {
  final String id;
  final String attendanceId;
  final String userId;
  final String userName;
  final String storeId;
  final DateTime requestedCheckIn;
  final DateTime requestedCheckOut;
  final String reason;
  final AdjustmentStatus status;
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? reviewNote;
  final DateTime? submittedAt;

  const AttendanceAdjustment({
    required this.id,
    required this.attendanceId,
    required this.userId,
    required this.userName,
    required this.storeId,
    required this.requestedCheckIn,
    required this.requestedCheckOut,
    required this.reason,
    this.status = AdjustmentStatus.pending,
    this.reviewedBy,
    this.reviewedAt,
    this.reviewNote,
    this.submittedAt,
  });

  bool get isPending => status == AdjustmentStatus.pending;
  bool get isApproved => status == AdjustmentStatus.approved;
  bool get isRejected => status == AdjustmentStatus.rejected;

  AttendanceAdjustment copyWith({
    String? id,
    String? attendanceId,
    String? userId,
    String? userName,
    String? storeId,
    DateTime? requestedCheckIn,
    DateTime? requestedCheckOut,
    String? reason,
    AdjustmentStatus? status,
    String? reviewedBy,
    DateTime? reviewedAt,
    String? reviewNote,
    DateTime? submittedAt,
  }) {
    return AttendanceAdjustment(
      id: id ?? this.id,
      attendanceId: attendanceId ?? this.attendanceId,
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      storeId: storeId ?? this.storeId,
      requestedCheckIn: requestedCheckIn ?? this.requestedCheckIn,
      requestedCheckOut: requestedCheckOut ?? this.requestedCheckOut,
      reason: reason ?? this.reason,
      status: status ?? this.status,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      reviewNote: reviewNote ?? this.reviewNote,
      submittedAt: submittedAt ?? this.submittedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AttendanceAdjustment &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          attendanceId == other.attendanceId &&
          userId == other.userId &&
          storeId == other.storeId &&
          status == other.status;

  @override
  int get hashCode =>
      id.hashCode ^
      attendanceId.hashCode ^
      userId.hashCode ^
      storeId.hashCode ^
      status.hashCode;
}
