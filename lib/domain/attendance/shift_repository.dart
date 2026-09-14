import 'shift.dart';

/// Repository interface for managing work shift definitions.
abstract class ShiftRepository {
  /// Fetches all active shifts.
  Future<List<Shift>> getShifts();

  /// Fetches a specific shift by its ID.
  Future<Shift?> getShiftById(String id);

  /// Saves (creates or updates) a shift definition.
  Future<void> saveShift(Shift shift);

  /// Deletes a shift by its ID.
  Future<void> deleteShift(String id);

  /// Real-time stream of shifts.
  Stream<List<Shift>> watchShifts();
}
