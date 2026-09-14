/// Domain entity representing a work shift.
class Shift {
  final String id;
  final String name; // e.g. "Ca Sáng", "Ca Chiều", "Ca Tối", "Ca Linh hoạt"
  final String startTime; // "HH:mm" e.g. "08:00"
  final String endTime; // "HH:mm" e.g. "12:00"
  final int gracePeriodMinutes; // e.g. 15 (minutes after startTime before late)
  final String type; // 'morning', 'afternoon', 'evening', 'flexible'
  final double standardWorkHours; // e.g. 4.0
  final bool isActive;

  const Shift({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.gracePeriodMinutes = 15,
    required this.type,
    this.standardWorkHours = 4.0,
    this.isActive = true,
  });

  /// Parse "HH:mm" to DateTime on the given base [date].
  DateTime getStartDateTime(DateTime date) {
    final parts = startTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 8;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Parse "HH:mm" to DateTime on the given base [date].
  DateTime getEndDateTime(DateTime date) {
    final parts = endTime.split(':');
    final hour = int.tryParse(parts[0]) ?? 12;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    return DateTime(date.year, date.month, date.day, hour, minute);
  }

  /// Calculates minutes late past start time + grace period.
  /// Returns 0 if checked in on time or before start time + grace period.
  int calculateLateMinutes(DateTime checkInTime, DateTime date) {
    if (type == 'flexible') return 0;
    final scheduledStart = getStartDateTime(date);
    final graceThreshold = scheduledStart.add(Duration(minutes: gracePeriodMinutes));
    if (checkInTime.isAfter(graceThreshold)) {
      return checkInTime.difference(scheduledStart).inMinutes;
    }
    return 0;
  }

  /// Calculates early leave minutes if checked out before scheduled end time.
  /// Returns 0 if checked out at or after scheduled end time.
  int calculateEarlyLeaveMinutes(DateTime checkOutTime, DateTime date) {
    if (type == 'flexible') return 0;
    final scheduledEnd = getEndDateTime(date);
    if (checkOutTime.isBefore(scheduledEnd)) {
      return scheduledEnd.difference(checkOutTime).inMinutes;
    }
    return 0;
  }

  /// Calculates overtime minutes if checked out after scheduled end time.
  /// Returns 0 if checked out at or before scheduled end time.
  int calculateOvertimeMinutes(DateTime checkOutTime, DateTime date) {
    if (type == 'flexible') return 0;
    final scheduledEnd = getEndDateTime(date);
    if (checkOutTime.isAfter(scheduledEnd)) {
      return checkOutTime.difference(scheduledEnd).inMinutes;
    }
    return 0;
  }

  Shift copyWith({
    String? id,
    String? name,
    String? startTime,
    String? endTime,
    int? gracePeriodMinutes,
    String? type,
    double? standardWorkHours,
    bool? isActive,
  }) {
    return Shift(
      id: id ?? this.id,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      gracePeriodMinutes: gracePeriodMinutes ?? this.gracePeriodMinutes,
      type: type ?? this.type,
      standardWorkHours: standardWorkHours ?? this.standardWorkHours,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Standard default seed shifts for convenience.
  static List<Shift> defaultShifts() {
    return const [
      Shift(
        id: 'shift_morning',
        name: 'Ca Sáng',
        startTime: '08:00',
        endTime: '12:00',
        gracePeriodMinutes: 15,
        type: 'morning',
        standardWorkHours: 4.0,
      ),
      Shift(
        id: 'shift_afternoon',
        name: 'Ca Chiều',
        startTime: '13:00',
        endTime: '17:30',
        gracePeriodMinutes: 15,
        type: 'afternoon',
        standardWorkHours: 4.5,
      ),
      Shift(
        id: 'shift_evening',
        name: 'Ca Tối',
        startTime: '17:30',
        endTime: '22:00',
        gracePeriodMinutes: 15,
        type: 'evening',
        standardWorkHours: 4.5,
      ),
      Shift(
        id: 'shift_flexible',
        name: 'Ca Linh hoạt',
        startTime: '08:00',
        endTime: '22:00',
        gracePeriodMinutes: 60,
        type: 'flexible',
        standardWorkHours: 8.0,
      ),
    ];
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Shift &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name &&
          startTime == other.startTime &&
          endTime == other.endTime &&
          gracePeriodMinutes == other.gracePeriodMinutes &&
          type == other.type &&
          standardWorkHours == other.standardWorkHours &&
          isActive == other.isActive;

  @override
  int get hashCode =>
      id.hashCode ^
      name.hashCode ^
      startTime.hashCode ^
      endTime.hashCode ^
      gracePeriodMinutes.hashCode ^
      type.hashCode ^
      standardWorkHours.hashCode ^
      isActive.hashCode;
}
