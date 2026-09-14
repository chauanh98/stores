import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/reports/overview_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/customer_debt_transaction.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/domain/repositories/customer_repository.dart';
import 'package:stores/domain/repositories/inventory_repository.dart';
import 'package:stores/domain/repositories/product_repository.dart';
import 'package:stores/domain/repositories/supplier_repository.dart';

// ============================================================================
// CONTRACT M4: ATTENDANCE, SHIFT, GEOFENCE & ADJUSTMENT DOMAIN ENTITIES
// ============================================================================

/// Shift definitions matching PROJECT.md § Attendance & Shift Contract (M4)
class Shift {
  final String id;
  final String name;
  final String startTime; // 'HH:mm', e.g. '08:00'
  final String endTime; // 'HH:mm', e.g. '12:00'
  final int gracePeriodMinutes; // e.g. 15
  final String type; // 'morning', 'afternoon', 'evening', 'flexible'

  const Shift({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.gracePeriodMinutes = 15,
    this.type = 'fixed',
  });

  int get startHour => int.parse(startTime.split(':')[0]);
  int get startMinute => int.parse(startTime.split(':')[1]);
  int get endHour => int.parse(endTime.split(':')[0]);
  int get endMinute => int.parse(endTime.split(':')[1]);

  DateTime getStartDateTime(DateTime date) {
    return DateTime(date.year, date.month, date.day, startHour, startMinute);
  }

  DateTime getGraceDateTime(DateTime date) {
    return getStartDateTime(date).add(Duration(minutes: gracePeriodMinutes));
  }

  DateTime getEndDateTime(DateTime date) {
    return DateTime(date.year, date.month, date.day, endHour, endMinute);
  }
}

/// Status of staff attendance record
enum AttendanceStatus {
  onTime, // Đúng giờ
  late, // Đi muộn
  earlyLeave, // Về sớm
  overtime, // Tăng ca (OT)
  absent, // Vắng mặt
  adjusted, // Đã điều chỉnh công
}

/// Status of attendance adjustment request
enum AdjustmentStatus {
  pending, // Đang chờ duyệt
  approved, // Đã duyệt
  rejected, // Từ chối
}

/// Store Geofence GPS Configuration
class StoreGpsConfig {
  final String storeId;
  final String storeName;
  final double latitude;
  final double longitude;
  final double allowedRadiusMeters; // standard <= 150m

  const StoreGpsConfig({
    required this.storeId,
    required this.storeName,
    required this.latitude,
    required this.longitude,
    this.allowedRadiusMeters = 150.0,
  });
}

/// Attendance Record
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
  final double checkInLat;
  final double checkInLng;
  final bool isGpsValid;
  final String? explanationReason;

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
    required this.status,
    this.lateMinutes = 0,
    this.earlyLeaveMinutes = 0,
    this.overtimeMinutes = 0,
    required this.checkInLat,
    required this.checkInLng,
    required this.isGpsValid,
    this.explanationReason,
  });

  double get workHours {
    if (checkOutTime == null) return 0.0;
    final diffMinutes = checkOutTime!.difference(checkInTime).inMinutes;
    return (diffMinutes / 60.0).clamp(0.0, 24.0);
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
    double? checkInLat,
    double? checkInLng,
    bool? isGpsValid,
    String? explanationReason,
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
      checkInLat: checkInLat ?? this.checkInLat,
      checkInLng: checkInLng ?? this.checkInLng,
      isGpsValid: isGpsValid ?? this.isGpsValid,
      explanationReason: explanationReason ?? this.explanationReason,
    );
  }
}

/// Attendance Adjustment Request
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
  });

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
    );
  }
}

// ============================================================================
// CORE ENGINES: HAVERSINE GPS, ATTENDANCE EVALUATION, TIMESHEET, DEBT
// ============================================================================

/// Pure Dart Haversine Geodesic Distance Helper
class GeoDistanceHelper {
  static const double earthRadiusMeters = 6371000.0;

  static double haversineDistance(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final rLat1 = _degToRad(lat1);
    final rLat2 = _degToRad(lat2);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(rLat1) * math.cos(rLat2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));

    return earthRadiusMeters * c;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);

  static bool isWithinStoreRadius({
    required double userLat,
    required double userLng,
    required StoreGpsConfig storeConfig,
  }) {
    final distance = haversineDistance(
      userLat,
      userLng,
      storeConfig.latitude,
      storeConfig.longitude,
    );
    // Exact specification: <= allowedRadiusMeters is valid
    return distance <= storeConfig.allowedRadiusMeters;
  }

  /// Calculates a point at exact distance directly North from origin
  static ({double lat, double lng}) pointAtExactDistanceMeters({
    required double originLat,
    required double originLng,
    required double distanceMeters,
  }) {
    final deltaLat = (distanceMeters / earthRadiusMeters) * (180.0 / math.pi);
    return (lat: originLat + deltaLat, lng: originLng);
  }
}

/// Attendance Status Evaluation Engine
class AttendanceEvaluationEngine {
  /// Evaluates Check-In: GPS radius validation, grace period, late minutes
  static AttendanceRecord createCheckIn({
    required String id,
    required UserAccount user,
    required StoreGpsConfig storeConfig,
    required Shift shift,
    required DateTime checkInTime,
    required double userLat,
    required double userLng,
    String? explanationReason,
  }) {
    final distance = GeoDistanceHelper.haversineDistance(
      userLat,
      userLng,
      storeConfig.latitude,
      storeConfig.longitude,
    );
    final isGpsValid = distance <= storeConfig.allowedRadiusMeters;

    final shiftStart = shift.getStartDateTime(checkInTime);
    final shiftGrace = shift.getGraceDateTime(checkInTime);

    int lateMinutes = 0;
    AttendanceStatus status = AttendanceStatus.onTime;

    if (checkInTime.isAfter(shiftGrace)) {
      lateMinutes = checkInTime.difference(shiftStart).inMinutes;
      status = AttendanceStatus.late;
    }

    return AttendanceRecord(
      id: id,
      userId: user.username,
      userName: user.displayName ?? user.username,
      storeId: storeConfig.storeId,
      shiftId: shift.id,
      shiftName: shift.name,
      date: DateTime(checkInTime.year, checkInTime.month, checkInTime.day),
      checkInTime: checkInTime,
      status: status,
      lateMinutes: lateMinutes,
      checkInLat: userLat,
      checkInLng: userLng,
      isGpsValid: isGpsValid,
      explanationReason: !isGpsValid ? explanationReason : null,
    );
  }

  /// Evaluates Check-Out: early leave, overtime (OT)
  static AttendanceRecord completeCheckOut({
    required AttendanceRecord record,
    required Shift shift,
    required DateTime checkOutTime,
  }) {
    final shiftEnd = shift.getEndDateTime(checkOutTime);

    int earlyLeaveMinutes = 0;
    int overtimeMinutes = 0;
    AttendanceStatus status = record.status;

    if (checkOutTime.isBefore(shiftEnd)) {
      earlyLeaveMinutes = shiftEnd.difference(checkOutTime).inMinutes;
      if (status == AttendanceStatus.onTime) {
        status = AttendanceStatus.earlyLeave;
      }
    } else if (checkOutTime.isAfter(shiftEnd)) {
      overtimeMinutes = checkOutTime.difference(shiftEnd).inMinutes;
      if (overtimeMinutes >= 15 && status == AttendanceStatus.onTime) {
        status = AttendanceStatus.overtime;
      }
    }

    return record.copyWith(
      checkOutTime: checkOutTime,
      earlyLeaveMinutes: earlyLeaveMinutes,
      overtimeMinutes: overtimeMinutes,
      status: status,
    );
  }
}

/// Monthly Timesheet Aggregation
class MonthlyTimesheetSummary {
  final String userId;
  final String userName;
  final int totalShifts;
  final int completedShifts;
  final double totalHours;
  final int lateCount;
  final int earlyLeaveCount;
  final int totalOtMinutes;

  const MonthlyTimesheetSummary({
    required this.userId,
    required this.userName,
    required this.totalShifts,
    required this.completedShifts,
    required this.totalHours,
    required this.lateCount,
    required this.earlyLeaveCount,
    required this.totalOtMinutes,
  });

  static MonthlyTimesheetSummary aggregate(
    String userId,
    String userName,
    List<AttendanceRecord> records,
  ) {
    final userRecords = records.where((r) => r.userId == userId).toList();
    final completed = userRecords.where((r) => r.checkOutTime != null).toList();
    final totalHours = completed.fold<double>(0.0, (sum, r) => sum + r.workHours);
    final lateCount = userRecords.where((r) => r.lateMinutes > 0).length;
    final earlyCount = userRecords.where((r) => r.earlyLeaveMinutes > 0).length;
    final totalOt = userRecords.fold<int>(0, (sum, r) => sum + r.overtimeMinutes);

    return MonthlyTimesheetSummary(
      userId: userId,
      userName: userName,
      totalShifts: userRecords.length,
      completedShifts: completed.length,
      totalHours: double.parse(totalHours.toStringAsFixed(2)),
      lateCount: lateCount,
      earlyLeaveCount: earlyCount,
      totalOtMinutes: totalOt,
    );
  }
}

/// Live Attendance Dashboard Aggregator
class LiveAttendanceSummary {
  final String storeId;
  final List<AttendanceRecord> activeWorking; // Checked-in, not checked out
  final List<AttendanceRecord> completedToday;
  final List<AttendanceRecord> lateToday;
  final List<String> absentStaff;

  const LiveAttendanceSummary({
    required this.storeId,
    required this.activeWorking,
    required this.completedToday,
    required this.lateToday,
    required this.absentStaff,
  });

  static LiveAttendanceSummary compute({
    required String storeId,
    required List<AttendanceRecord> allTodayRecords,
    required List<String> scheduledStaffIds,
  }) {
    final storeRecords = allTodayRecords.where((r) => r.storeId == storeId).toList();
    final active = storeRecords.where((r) => r.checkOutTime == null).toList();
    final completed = storeRecords.where((r) => r.checkOutTime != null).toList();
    final late = storeRecords.where((r) => r.lateMinutes > 0).toList();

    final attendedUserIds = storeRecords.map((r) => r.userId).toSet();
    final absent = scheduledStaffIds.where((id) => !attendedUserIds.contains(id)).toList();

    return LiveAttendanceSummary(
      storeId: storeId,
      activeWorking: active,
      completedToday: completed,
      lateToday: late,
      absentStaff: absent,
    );
  }
}

/// Customer Debt Engine (R1)
class CustomerDebtEngine {
  static List<Customer> filterCustomers({
    required List<Customer> customers,
    required CustomerDebtFilter filter,
    String searchQuery = '',
  }) {
    var list = customers;

    if (searchQuery.trim().isNotEmpty) {
      final q = searchQuery.trim().toLowerCase();
      list = list.where((c) {
        return c.name.toLowerCase().contains(q) ||
            c.phone.toLowerCase().contains(q) ||
            c.email.toLowerCase().contains(q);
      }).toList();
    }

    switch (filter) {
      case CustomerDebtFilter.all:
        return list;
      case CustomerDebtFilter.inDebt:
        final inDebtList = list.where((c) => (c.currentDebt ?? 0) > 0).toList()
          ..sort((a, b) => b.displayCurrentDebt.compareTo(a.displayCurrentDebt));
        return inDebtList;
      case CustomerDebtFilter.cleared:
        return list.where((c) => (c.currentDebt ?? 0) <= 0).toList();
    }
  }

  static double calculateLiveTotalDebt(List<Customer> customers) {
    return customers.fold<double>(
      0.0,
      (sum, c) => sum + (c.displayCurrentDebt > 0 ? c.displayCurrentDebt : 0.0),
    );
  }
}

/// Supplier Debt Engine (R2)
class SupplierDebtEngine {
  static ({
    Supplier updatedSupplier,
    SupplierDebtTransaction? debtTransaction,
  }) processImportDebt({
    required Supplier supplier,
    required double totalAmount,
    required double paidAmount,
    String? importCode,
    String? note,
    String createdBy = 'Admin',
  }) {
    final debtIncrease = (totalAmount - paidAmount).clamp(0.0, double.infinity);
    final newTotalPurchase = supplier.totalPurchase + totalAmount;
    final newDebt = supplier.currentDebt + debtIncrease;

    SupplierDebtTransaction? tx;
    if (debtIncrease > 0) {
      tx = SupplierDebtTransaction(
        id: 'TX_IMP_${DateTime.now().millisecondsSinceEpoch}',
        supplierId: supplier.id,
        date: DateTime.now(),
        type: SupplierDebtType.importBill,
        amount: debtIncrease,
        remainingDebt: newDebt,
        referenceCode: importCode ?? 'PN_${DateTime.now().millisecondsSinceEpoch}',
        note: note ?? 'Nhập hàng phát sinh công nợ',
        createdBy: createdBy,
      );
    }

    final updated = supplier.copyWith(
      totalPurchase: newTotalPurchase,
      currentDebt: newDebt,
    );

    return (updatedSupplier: updated, debtTransaction: tx);
  }
}

// ============================================================================
// TEST FAKES AND REPOSITORY IMPLEMENTATIONS
// ============================================================================

class FakeCustomerRepository implements CustomerRepository {
  final List<Customer> customers;
  final List<CustomerDebtTransaction> debtTransactions = [];

  FakeCustomerRepository([List<Customer>? initial])
      : customers = initial != null ? List<Customer>.from(initial) : [];

  @override
  Stream<List<Customer>> watchAll() => Stream.value(customers);

  @override
  Future<Customer?> fetchById(String id) async {
    try {
      return customers.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Customer customer) async {
    final idx = customers.indexWhere((c) => c.id == customer.id);
    if (idx >= 0) {
      customers[idx] = customer;
    } else {
      customers.add(customer);
    }
  }

  @override
  Future<void> delete(String id) async {
    customers.removeWhere((c) => c.id == id);
  }
}

class FakeSupplierRepository implements SupplierRepository {
  final List<Supplier> suppliers;
  final List<SupplierDebtTransaction> recordedTransactions = [];

  FakeSupplierRepository([List<Supplier>? initial])
      : suppliers = initial != null ? List<Supplier>.from(initial) : [];

  @override
  Stream<List<Supplier>> watchAll({String? storeId}) => Stream.value(suppliers);

  Future<List<Supplier>> fetchAll({String? storeId}) async => suppliers;

  @override
  Future<Supplier?> fetchById(String id, {String? storeId}) async {
    try {
      return suppliers.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Supplier supplier, {String? storeId}) async {
    final idx = suppliers.indexWhere((s) => s.id == supplier.id);
    if (idx >= 0) {
      suppliers[idx] = supplier;
    } else {
      suppliers.add(supplier);
    }
  }

  @override
  Future<void> delete(String id, {String? storeId}) async {
    suppliers.removeWhere((s) => s.id == id);
  }

  @override
  Stream<List<SupplierDebtTransaction>> watchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) {
    return Stream.value(
      recordedTransactions.where((t) => t.supplierId == supplierId).toList(),
    );
  }

  @override
  Future<void> recordDebtTransaction(
    SupplierDebtTransaction transaction, {
    String? storeId,
  }) async {
    recordedTransactions.add(transaction);
  }

  @override
  Future<List<SupplierDebtTransaction>> fetchDebtTransactions(
    String supplierId, {
    String? storeId,
  }) async {
    return recordedTransactions.where((t) => t.supplierId == supplierId).toList();
  }
}

class FakeInventoryRepository implements InventoryRepository {
  final List<InventoryTransaction> transactions = [];

  FakeInventoryRepository([List<InventoryTransaction>? initial]) {
    if (initial != null) transactions.addAll(initial);
  }

  @override
  Future<void> record(InventoryTransaction tx) async {
    transactions.add(tx);
  }

  @override
  Stream<List<InventoryTransaction>> watchByProduct(String productId) {
    return Stream.value(transactions.where((t) => t.productId == productId).toList());
  }

  @override
  Stream<List<InventoryTransaction>> watchImportsByDateRange(
    DateTime startDate,
    DateTime endDate,
  ) {
    return Stream.value(
      transactions.where((t) {
        return t.date.isAfter(startDate.subtract(const Duration(seconds: 1))) &&
            t.date.isBefore(endDate.add(const Duration(seconds: 1)));
      }).toList(),
    );
  }
}

class FakeProductRepository implements ProductRepository {
  final List<Product> products;

  FakeProductRepository([List<Product>? initial])
      : products = initial != null ? List<Product>.from(initial) : [];

  @override
  Stream<List<Product>> watchAll() => Stream.value(products);

  @override
  Future<List<Product>> fetchAll() async => products;

  @override
  Future<Product?> fetchById(String id) async {
    try {
      return products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> upsert(Product product) async {
    final idx = products.indexWhere((p) => p.id == product.id);
    if (idx >= 0) {
      products[idx] = product;
    } else {
      products.add(product);
    }
  }

  @override
  Future<void> delete(String id) async {
    products.removeWhere((p) => p.id == id);
  }

  @override
  Future<void> updateStock(String id, int newStock) async {
    final idx = products.indexWhere((p) => p.id == id);
    if (idx >= 0) {
      final updatedStocks = Map<String, int>.from(products[idx].branchStocks);
      updatedStocks['store_001'] = newStock;
      products[idx] = products[idx].copyWith(branchStocks: updatedStocks);
    }
  }
}

class FakeAttendanceRepository {
  final List<AttendanceRecord> records = [];
  final List<AttendanceAdjustment> adjustments = [];
  final List<Shift> shifts = [];
  final Map<String, StoreGpsConfig> storeConfigs = {};

  void seedDefaultShifts() {
    shifts.addAll([
      const Shift(
        id: 'shift_morning',
        name: 'Ca Sáng (08:00 - 12:00)',
        startTime: '08:00',
        endTime: '12:00',
        gracePeriodMinutes: 15,
        type: 'morning',
      ),
      const Shift(
        id: 'shift_afternoon',
        name: 'Ca Chiều (13:00 - 17:30)',
        startTime: '13:00',
        endTime: '17:30',
        gracePeriodMinutes: 15,
        type: 'afternoon',
      ),
      const Shift(
        id: 'shift_evening',
        name: 'Ca Tối (17:30 - 22:00)',
        startTime: '17:30',
        endTime: '22:00',
        gracePeriodMinutes: 10,
        type: 'evening',
      ),
      const Shift(
        id: 'shift_flexible',
        name: 'Ca Linh Hoạt',
        startTime: '08:00',
        endTime: '17:00',
        gracePeriodMinutes: 30,
        type: 'flexible',
      ),
    ]);
  }

  void seedDefaultStoreGps() {
    // Chi nhánh Đông Thắng (store_001)
    storeConfigs['store_001'] = const StoreGpsConfig(
      storeId: 'store_001',
      storeName: 'Chi nhánh Đông Thắng',
      latitude: 10.7769,
      longitude: 106.7009,
      allowedRadiusMeters: 150.0,
    );
    // Chi nhánh Thới Bình (store_002)
    storeConfigs['store_002'] = const StoreGpsConfig(
      storeId: 'store_002',
      storeName: 'Chi nhánh Thới Bình',
      latitude: 10.7626,
      longitude: 106.6820,
      allowedRadiusMeters: 150.0,
    );
  }

  Future<void> saveRecord(AttendanceRecord record) async {
    final idx = records.indexWhere((r) => r.id == record.id);
    if (idx >= 0) {
      records[idx] = record;
    } else {
      records.add(record);
    }
  }

  Future<AttendanceRecord?> getRecordById(String id) async {
    try {
      return records.firstWhere((r) => r.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<List<AttendanceRecord>> getRecordsForUser(String userId, int month, int year) async {
    return records.where((r) {
      return r.userId == userId && r.date.month == month && r.date.year == year;
    }).toList();
  }

  Future<void> submitAdjustment(AttendanceAdjustment adj) async {
    adjustments.add(adj);
  }

  Future<void> reviewAdjustment({
    required String adjustmentId,
    required bool approve,
    required String reviewerUsername,
  }) async {
    final idx = adjustments.indexWhere((a) => a.id == adjustmentId);
    if (idx < 0) return;

    final adj = adjustments[idx];
    final newStatus = approve ? AdjustmentStatus.approved : AdjustmentStatus.rejected;
    final updatedAdj = adj.copyWith(
      status: newStatus,
      reviewedBy: reviewerUsername,
      reviewedAt: DateTime.now(),
    );
    adjustments[idx] = updatedAdj;

    if (approve) {
      final recIdx = records.indexWhere((r) => r.id == adj.attendanceId);
      if (recIdx >= 0) {
        final existing = records[recIdx];
        final updatedRecord = existing.copyWith(
          checkInTime: adj.requestedCheckIn,
          checkOutTime: adj.requestedCheckOut,
          status: AttendanceStatus.adjusted,
          lateMinutes: 0,
          earlyLeaveMinutes: 0,
        );
        records[recIdx] = updatedRecord;
      }
    }
  }
}

// ============================================================================
// WIDGET HARNESS HELPERS
// ============================================================================

class FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  FakeAuthNotifier([UserAccount? user])
      : super(user ??
            const UserAccount(
              username: 'admin_test',
              displayName: 'Quản trị viên',
              role: 'admin',
              storeId: 'store_001',
            ));

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

Widget buildKiotVietE2ETestHarness({
  required Widget child,
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      authProvider.overrideWith((ref) => FakeAuthNotifier()),
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      branchesProvider.overrideWithValue(const [
        Branch('store_001', 'Chi nhánh Đông Thắng'),
        Branch('store_002', 'Chi nhánh Thới Bình'),
      ]),
      ...overrides,
    ],
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: Scaffold(body: child),
    ),
  );
}
