import '../../domain/attendance/shift.dart';

class ShiftModel {
  final String id;
  final String name;
  final String startTime;
  final String endTime;
  final int gracePeriodMinutes;
  final String type;
  final double standardWorkHours;
  final bool isActive;

  const ShiftModel({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.gracePeriodMinutes = 15,
    required this.type,
    this.standardWorkHours = 4.0,
    this.isActive = true,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'startTime': startTime,
      'endTime': endTime,
      'gracePeriodMinutes': gracePeriodMinutes,
      'type': type,
      'standardWorkHours': standardWorkHours,
      'isActive': isActive,
    };
  }

  factory ShiftModel.fromMap(Map<dynamic, dynamic> map, {String? id}) {
    return ShiftModel(
      id: id ?? map['id']?.toString() ?? '',
      name: map['name']?.toString() ?? '',
      startTime: map['startTime']?.toString() ?? '08:00',
      endTime: map['endTime']?.toString() ?? '12:00',
      gracePeriodMinutes: (map['gracePeriodMinutes'] as num?)?.toInt() ?? 15,
      type: map['type']?.toString() ?? 'morning',
      standardWorkHours: (map['standardWorkHours'] as num?)?.toDouble() ?? 4.0,
      isActive: map['isActive'] == null ? true : (map['isActive'] as bool),
    );
  }

  Shift toDomain() {
    return Shift(
      id: id,
      name: name,
      startTime: startTime,
      endTime: endTime,
      gracePeriodMinutes: gracePeriodMinutes,
      type: type,
      standardWorkHours: standardWorkHours,
      isActive: isActive,
    );
  }

  factory ShiftModel.fromDomain(Shift shift) {
    return ShiftModel(
      id: shift.id,
      name: shift.name,
      startTime: shift.startTime,
      endTime: shift.endTime,
      gracePeriodMinutes: shift.gracePeriodMinutes,
      type: shift.type,
      standardWorkHours: shift.standardWorkHours,
      isActive: shift.isActive,
    );
  }
}
