import 'dart:math' as math;

/// Status of the shift check-in window.
enum ShiftWindowStatus {
  open,
  closed,
  upcoming,
}

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
  /// Cross-midnight fix: If end time is before start time, end is on the next day.
  DateTime getEndDateTime(DateTime date) {
    final startParts = startTime.split(':');
    final startHour = int.tryParse(startParts[0]) ?? 8;
    final startMinute =
        startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;

    final parts = endTime.split(':');
    final endHour = int.tryParse(parts[0]) ?? 12;
    final endMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    var targetDate = date;
    if (endHour < startHour ||
        (endHour == startHour && endMinute < startMinute)) {
      targetDate = date.add(const Duration(days: 1));
    }
    return DateTime(
        targetDate.year, targetDate.month, targetDate.day, endHour, endMinute);
  }

  /// The check-in window opens 60 minutes before scheduled start time.
  DateTime getCheckInWindowStart(DateTime date) =>
      getStartDateTime(date).subtract(const Duration(minutes: 60));

  /// The check-in window ends when the shift ends.
  DateTime getCheckInWindowEnd(DateTime date) => getEndDateTime(date);

  /// Computes the check-in window status for [checkTime] on the given [date].
  ShiftWindowStatus getWindowStatus(DateTime checkTime, [DateTime? date]) {
    final baseDate =
        date ?? DateTime(checkTime.year, checkTime.month, checkTime.day);

    final startParts = startTime.split(':');
    final startHour = int.tryParse(startParts[0]) ?? 8;
    final startMinute =
        startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;

    final parts = endTime.split(':');
    final endHour = int.tryParse(parts[0]) ?? 12;
    final endMinute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;

    final isOvernight = endHour < startHour ||
        (endHour == startHour && endMinute < startMinute);

    if (isOvernight) {
      final yesterday = baseDate.subtract(const Duration(days: 1));
      final yesterdayStart = getCheckInWindowStart(yesterday);
      final yesterdayEnd = getCheckInWindowEnd(yesterday);
      if (!checkTime.isBefore(yesterdayStart) &&
          !checkTime.isAfter(yesterdayEnd)) {
        return ShiftWindowStatus.open;
      }
    }

    final windowStart = getCheckInWindowStart(baseDate);
    final windowEnd = getCheckInWindowEnd(baseDate);

    if (checkTime.isAfter(windowEnd)) {
      return ShiftWindowStatus.closed;
    }
    if (checkTime.isBefore(windowStart)) {
      return ShiftWindowStatus.upcoming;
    }
    return ShiftWindowStatus.open;
  }

  /// Whether the shift is currently open for check-in.
  bool isCheckInWindowOpen(DateTime checkTime, [DateTime? date]) =>
      getWindowStatus(checkTime, date) == ShiftWindowStatus.open;

  /// Calculates minutes late past start time + grace period.
  /// Returns 0 if checked in on time or before start time + grace period.
  int calculateLateMinutes(DateTime checkInTime, DateTime date) {
    if (type == 'flexible') return 0;
    final scheduledStart = getStartDateTime(date);
    final graceThreshold =
        scheduledStart.add(Duration(minutes: gracePeriodMinutes));
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

  /// Calculates overtime minutes.
  ///
  /// For flexible shifts, overtime is the excess worked minutes beyond standard work duration.
  /// For fixed shifts, overtime requires both:
  /// 1. Checkout occurs after scheduled end time ([scheduledEnd]).
  /// 2. Total worked duration exceeds [standardWorkMinutes].
  /// Late arrival is compensated first before any overtime is credited.
  /// Returns 0 if conditions are not satisfied.
  int calculateOvertimeMinutes(
    DateTime checkOutTime,
    DateTime date, {
    DateTime? checkInTime,
  }) {
    final effectiveCheckIn = checkInTime ?? getStartDateTime(date);
    final actualWorkedMinutes =
        checkOutTime.difference(effectiveCheckIn).inMinutes;
    final standardWorkMinutes = (standardWorkHours * 60).round();

    if (type == 'flexible') {
      return actualWorkedMinutes > standardWorkMinutes
          ? (actualWorkedMinutes - standardWorkMinutes)
          : 0;
    }

    final scheduledEnd = getEndDateTime(date);
    if (checkOutTime.isAfter(scheduledEnd) &&
        actualWorkedMinutes > standardWorkMinutes) {
      final pastScheduledEndMinutes =
          checkOutTime.difference(scheduledEnd).inMinutes;
      final excessWorkedMinutes = actualWorkedMinutes - standardWorkMinutes;
      return math.min(pastScheduledEndMinutes, excessWorkedMinutes);
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

  /// Automatically selects the best shift candidate for the given [now] timestamp.
  ///
  /// Evaluates active shifts:
  /// 1. Finds shifts whose check-in window is currently open. If any, prioritizes
  ///    fixed shifts over flexible ones and picks the one closest to its start time.
  /// 2. If no shift is open, finds the earliest upcoming shift today.
  /// 3. Falls back to the first active shift (or null if empty).
  static Shift? findBestShiftForTime(List<Shift> shifts, DateTime now) {
    final active = shifts.where((s) => s.isActive).toList();
    if (active.isEmpty) return shifts.firstOrNull;

    final open = active
        .where((s) => s.getWindowStatus(now, now) == ShiftWindowStatus.open)
        .toList();
    if (open.isNotEmpty) {
      open.sort((a, b) {
        final aIsFlex = a.type == 'flexible';
        final bIsFlex = b.type == 'flexible';
        if (aIsFlex != bIsFlex) {
          return aIsFlex ? 1 : -1;
        }
        final aDiff = (now.difference(a.getStartDateTime(now)).inMinutes).abs();
        final bDiff = (now.difference(b.getStartDateTime(now)).inMinutes).abs();
        return aDiff.compareTo(bDiff);
      });
      return open.first;
    }

    final upcoming = active
        .where((s) => s.getWindowStatus(now, now) == ShiftWindowStatus.upcoming)
        .toList();
    if (upcoming.isNotEmpty) {
      upcoming.sort(
          (a, b) => a.getStartDateTime(now).compareTo(b.getStartDateTime(now)));
      return upcoming.first;
    }

    return active.firstOrNull;
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
