import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/data/models/attendance_adjustment_model.dart';
import 'package:stores/data/models/attendance_record_model.dart';
import 'package:stores/data/models/shift_model.dart';
import 'package:stores/data/models/store_gps_config_model.dart';
import 'package:stores/domain/attendance/shift.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttendanceRemoteDataSource', () {
    late MockFirebaseDatabase mockDb;
    late AttendanceRemoteDataSource dataSource;
    late DefaultLocationService locationService;
    const shiftsPath = 'shifts';
    const attendancesPath = 'attendances';
    const adjustmentsPath = 'attendance_adjustments';
    const storeId = 'store_test_001';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      locationService = DefaultLocationService();
      dataSource = AttendanceRemoteDataSource(
        db: mockDb,
        locationService: locationService,
      );
    });

    group('watchShifts() - Streaming & Empty Fallback', () {
      test('emits Shift.defaultShifts() when shifts node is empty or null', () async {
        final ref = mockDb.getOrCreateRef(shiftsPath);
        final completer = Completer<List<ShiftModel>>();
        final sub = dataSource.watchShifts().listen((shifts) {
          if (!completer.isCompleted) completer.complete(shifts);
        });

        ref.emitNullValue();

        final result = await completer.future.timeout(const Duration(milliseconds: 150));
        expect(result, isNotEmpty);
        expect(result.length, equals(Shift.defaultShifts().length));
        final types = result.map((s) => s.type).toList();
        expect(types, containsAll(['morning', 'afternoon', 'evening', 'flexible']));

        await sub.cancel();
      });

      test('streams custom shifts when node contains shift data', () async {
        final ref = mockDb.getOrCreateRef(shiftsPath);
        final emissions = <List<ShiftModel>>[];
        final sub = dataSource.watchShifts().listen(emissions.add);

        ref.emitValue({
          'custom_shift_1': {
            'id': 'custom_shift_1',
            'name': 'Ca Sáng Sớm',
            'startTime': '06:00',
            'endTime': '10:00',
            'gracePeriodMinutes': 10,
            'type': 'morning',
            'standardWorkHours': 4.0,
            'isActive': true,
          },
        });

        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(1));
        expect(emissions.first.first.name, equals('Ca Sáng Sớm'));

        await sub.cancel();
      });
    });

    group('watchAttendances() - Streaming & Client-Side Filtering', () {
      test('emits [] when attendances node is empty or null', () async {
        final ref = mockDb.getOrCreateRef(attendancesPath);
        final completer = Completer<List<AttendanceRecordModel>>();
        final sub = dataSource
            .watchAttendances(storeId: storeId, dateStr: '2026-09-19')
            .listen((records) {
          if (!completer.isCompleted) completer.complete(records);
        });

        ref.emitNullValue();

        final result = await completer.future.timeout(const Duration(milliseconds: 400));
        expect(result, isEmpty);

        await sub.cancel();
      });

      test('filters attendances strictly by storeId and dateStr', () async {
        final ref = mockDb.getOrCreateRef(attendancesPath);
        final emissions = <List<AttendanceRecordModel>>[];
        final sub = dataSource
            .watchAttendances(storeId: storeId, dateStr: '2026-09-19')
            .listen(emissions.add);

        ref.emitValue({
          'att_match': {
            'id': 'att_match',
            'userId': 'user_1',
            'userName': 'User One',
            'storeId': storeId,
            'shiftId': 'shift_morning',
            'shiftName': 'Ca Sáng',
            'date': '2026-09-19',
            'checkInTime': '2026-09-19T08:00:00.000Z',
            'checkInGpsLat': 10.035,
            'checkInGpsLng': 105.788,
            'isGpsValid': true,
          },
          'att_wrong_date': {
            'id': 'att_wrong_date',
            'userId': 'user_2',
            'userName': 'User Two',
            'storeId': storeId,
            'shiftId': 'shift_morning',
            'shiftName': 'Ca Sáng',
            'date': '2026-09-20', // Different date
            'checkInTime': '2026-09-20T08:00:00.000Z',
            'checkInGpsLat': 10.035,
            'checkInGpsLng': 105.788,
            'isGpsValid': true,
          },
          'att_wrong_store': {
            'id': 'att_wrong_store',
            'userId': 'user_3',
            'userName': 'User Three',
            'storeId': 'store_other_999', // Different store
            'shiftId': 'shift_morning',
            'shiftName': 'Ca Sáng',
            'date': '2026-09-19',
            'checkInTime': '2026-09-19T08:00:00.000Z',
            'checkInGpsLat': 10.035,
            'checkInGpsLng': 105.788,
            'isGpsValid': true,
          },
        });

        await Future.delayed(const Duration(milliseconds: 270));

        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(1));
        expect(emissions.first.first.id, equals('att_match'));
        expect(emissions.first.first.userId, equals('user_1'));

        await sub.cancel();
      });
    });

    group('watchAdjustments() - Streaming & Store Filtering', () {
      test('emits [] when adjustments node is empty or null', () async {
        final ref = mockDb.getOrCreateRef(adjustmentsPath);
        final completer = Completer<List<AttendanceAdjustmentModel>>();
        final sub = dataSource.watchAdjustments(storeId: storeId).listen((adj) {
          if (!completer.isCompleted) completer.complete(adj);
        });

        ref.emitNullValue();

        final result = await completer.future.timeout(const Duration(milliseconds: 150));
        expect(result, isEmpty);

        await sub.cancel();
      });

      test('filters adjustments by storeId when specified', () async {
        final ref = mockDb.getOrCreateRef(adjustmentsPath);
        final emissions = <List<AttendanceAdjustmentModel>>[];
        final sub = dataSource.watchAdjustments(storeId: storeId).listen(emissions.add);

        ref.emitValue({
          'adj_1': {
            'id': 'adj_1',
            'attendanceId': 'att_1',
            'userId': 'user_1',
            'userName': 'User One',
            'storeId': storeId,
            'requestedCheckIn': '2026-09-19T08:00:00.000Z',
            'requestedCheckOut': '2026-09-19T17:00:00.000Z',
            'reason': 'Quên chấm công ra',
            'status': 'pending',
          },
          'adj_2': {
            'id': 'adj_2',
            'attendanceId': 'att_2',
            'userId': 'user_99',
            'userName': 'User Other',
            'storeId': 'store_other', // Different store
            'requestedCheckIn': '2026-09-19T08:00:00.000Z',
            'requestedCheckOut': '2026-09-19T17:00:00.000Z',
            'reason': 'Lý do khác',
            'status': 'pending',
          },
        });

        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(1));
        expect(emissions.first.first.id, equals('adj_1'));
        expect(emissions.first.first.storeId, equals(storeId));

        await sub.cancel();
      });
    });

    group('Shifts CRUD & Auto-seeding', () {
      test('getShifts() seeds default shifts to Firebase RTDB if node is empty', () async {
        final shifts = await dataSource.getShifts();

        expect(shifts, isNotEmpty);
        expect(shifts.length, equals(Shift.defaultShifts().length));

        // Verify that default shifts were actually persisted to database via .set()
        final snap = await mockDb.getOrCreateRef(shiftsPath).get();
        expect(snap.exists, isTrue);
        expect(mockDb.recorder.hasCalled('set', path: 'shifts'), isTrue);
      });

      test('getShifts() returns existing shifts without re-seeding if present', () async {
        mockDb.seedData(shiftsPath, {
          'custom_1': {
            'id': 'custom_1',
            'name': 'Existing Custom Shift',
            'startTime': '09:00',
            'endTime': '18:00',
            'type': 'flexible',
          },
        });

        final shifts = await dataSource.getShifts();
        expect(shifts.length, equals(1));
        expect(shifts.first.name, equals('Existing Custom Shift'));
      });

      test('saveShift() writes shift model to shifts node', () async {
        const shift = ShiftModel(
          id: 'shift_save_test',
          name: 'Ca Tối Đặc Biệt',
          startTime: '18:00',
          endTime: '22:00',
          type: 'evening',
        );

        await dataSource.saveShift(shift);

        final snap = await mockDb.getOrCreateRef(shiftsPath).child('shift_save_test').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['name'], equals('Ca Tối Đặc Biệt'));
      });

      test('deleteShift() removes shift from database', () async {
        mockDb.seedData(shiftsPath, {
          'shift_to_delete': {'name': 'Delete Me'},
        });

        await dataSource.deleteShift('shift_to_delete');

        final snap = await mockDb.getOrCreateRef(shiftsPath).child('shift_to_delete').get();
        expect(snap.exists, isFalse);
      });
    });

    group('Attendances CRUD & Multi-criteria Filtering', () {
      final sampleAttendances = {
        'rec_1': {
          'id': 'rec_1',
          'userId': 'user_A',
          'userName': 'User A',
          'storeId': 'store_001',
          'shiftId': 'shift_1',
          'shiftName': 'Ca 1',
          'date': '2026-09-19',
          'checkInTime': '2026-09-19T08:00:00.000Z',
          'checkInGpsLat': 10.035,
          'checkInGpsLng': 105.788,
          'isGpsValid': true,
        },
        'rec_2': {
          'id': 'rec_2',
          'userId': 'user_B',
          'userName': 'User B',
          'storeId': 'store_001',
          'shiftId': 'shift_1',
          'shiftName': 'Ca 1',
          'date': '2026-09-19',
          'checkInTime': '2026-09-19T08:05:00.000Z',
          'checkInGpsLat': 10.035,
          'checkInGpsLng': 105.788,
          'isGpsValid': true,
        },
        'rec_3': {
          'id': 'rec_3',
          'userId': 'user_A',
          'userName': 'User A',
          'storeId': 'store_002', // Different store
          'shiftId': 'shift_1',
          'shiftName': 'Ca 1',
          'date': '2026-09-19',
          'checkInTime': '2026-09-19T08:00:00.000Z',
          'checkInGpsLat': 10.035,
          'checkInGpsLng': 105.788,
          'isGpsValid': true,
        },
      };

      test('getAttendances() filters by storeId, dateStr, and userId', () async {
        mockDb.seedData(attendancesPath, sampleAttendances);

        // Filter by store_001 and date 2026-09-19
        final storeRecords = await dataSource.getAttendances(
          storeId: 'store_001',
          dateStr: '2026-09-19',
        );
        expect(storeRecords.length, equals(2));

        // Filter by specific user user_A in store_001
        final userRecords = await dataSource.getAttendances(
          storeId: 'store_001',
          dateStr: '2026-09-19',
          userId: 'user_A',
        );
        expect(userRecords.length, equals(1));
        expect(userRecords.first.id, equals('rec_1'));
      });

      test('getAttendances() returns [] on empty node', () async {
        final records = await dataSource.getAttendances(storeId: 'store_001');
        expect(records, isEmpty);
      });

      test('saveAttendance() and updateAttendance() save records in database', () async {
        const record = AttendanceRecordModel(
          id: 'rec_new',
          userId: 'staff_1',
          userName: 'Staff One',
          storeId: 'store_001',
          shiftId: 'shift_morning',
          shiftName: 'Ca Sáng',
          date: '2026-09-19',
          checkInTime: '2026-09-19T08:00:00.000Z',
          checkInGpsLat: 10.035,
          checkInGpsLng: 105.788,
          isGpsValid: true,
        );

        await dataSource.saveAttendance(record);

        final snap = await mockDb.getOrCreateRef(attendancesPath).child('rec_new').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['userName'], equals('Staff One'));

        // Update record with checkout
        final updatedRecord = AttendanceRecordModel(
          id: record.id,
          userId: record.userId,
          userName: record.userName,
          storeId: record.storeId,
          shiftId: record.shiftId,
          shiftName: record.shiftName,
          date: record.date,
          checkInTime: record.checkInTime,
          checkInGpsLat: record.checkInGpsLat,
          checkInGpsLng: record.checkInGpsLng,
          isGpsValid: record.isGpsValid,
          checkOutTime: '2026-09-19T17:00:00.000Z',
          totalWorkHours: 8.0,
        );
        await dataSource.updateAttendance(updatedRecord);

        final updatedSnap = await mockDb.getOrCreateRef(attendancesPath).child('rec_new').get();
        expect((updatedSnap.value as Map)['checkOutTime'], equals('2026-09-19T17:00:00.000Z'));
      });
    });

    group('Adjustments CRUD & Filtering', () {
      test('getAdjustments() filters by storeId, userId, and status', () async {
        mockDb.seedData(adjustmentsPath, {
          'adj_A': {
            'id': 'adj_A',
            'attendanceId': 'att_1',
            'userId': 'u1',
            'userName': 'User 1',
            'storeId': 'store_001',
            'requestedCheckIn': '2026-09-19T08:00:00.000Z',
            'requestedCheckOut': '2026-09-19T17:00:00.000Z',
            'reason': 'Reason A',
            'status': 'pending',
          },
          'adj_B': {
            'id': 'adj_B',
            'attendanceId': 'att_2',
            'userId': 'u2',
            'userName': 'User 2',
            'storeId': 'store_001',
            'requestedCheckIn': '2026-09-19T08:00:00.000Z',
            'requestedCheckOut': '2026-09-19T17:00:00.000Z',
            'reason': 'Reason B',
            'status': 'approved',
          },
        });

        // Filter by pending status
        final pending = await dataSource.getAdjustments(
          storeId: 'store_001',
          status: 'pending',
        );
        expect(pending.length, equals(1));
        expect(pending.first.id, equals('adj_A'));

        // Filter by user u2
        final userAdjustments = await dataSource.getAdjustments(
          storeId: 'store_001',
          userId: 'u2',
        );
        expect(userAdjustments.length, equals(1));
        expect(userAdjustments.first.id, equals('adj_B'));
      });

      test('saveAdjustment() and updateAdjustment() operations', () async {
        const adj = AttendanceAdjustmentModel(
          id: 'adj_new',
          attendanceId: 'att_10',
          userId: 'staff_1',
          userName: 'Staff One',
          storeId: 'store_001',
          requestedCheckIn: '2026-09-19T08:00:00.000Z',
          requestedCheckOut: '2026-09-19T17:00:00.000Z',
          reason: 'Lỗi GPS',
          status: 'pending',
        );

        await dataSource.saveAdjustment(adj);

        final snap = await mockDb.getOrCreateRef(adjustmentsPath).child('adj_new').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['reason'], equals('Lỗi GPS'));

        final approved = AttendanceAdjustmentModel(
          id: adj.id,
          attendanceId: adj.attendanceId,
          userId: adj.userId,
          userName: adj.userName,
          storeId: adj.storeId,
          requestedCheckIn: adj.requestedCheckIn,
          requestedCheckOut: adj.requestedCheckOut,
          reason: adj.reason,
          status: 'approved',
          reviewedBy: 'supervisor_1',
        );
        await dataSource.updateAdjustment(approved);

        final updatedSnap = await mockDb.getOrCreateRef(adjustmentsPath).child('adj_new').get();
        expect((updatedSnap.value as Map)['status'], equals('approved'));
      });
    });

    group('Store GPS Config & Location Service', () {
      const storeGpsPath = 'stores/$storeId';

      test('getStoreGpsConfig() returns default config when database node is absent', () async {
        final config = await dataSource.getStoreGpsConfig(storeId);
        expect(config, isNotNull);
        expect(config!.storeId, equals(storeId));
        expect(config.latitude, equals(10.035));
        expect(config.longitude, equals(105.788));
      });

      test('saveStoreGpsConfig() writes GPS coordinates to store node', () async {
        const config = StoreGpsConfigModel(
          storeId: storeId,
          latitude: 10.123456,
          longitude: 105.654321,
          allowedRadiusMeters: 200.0,
          storeName: 'Chi nhánh Thới Bình',
          address: 'Thới Bình, Cà Mau',
        );

        await dataSource.saveStoreGpsConfig(config);

        final snap = await mockDb.getOrCreateRef(storeGpsPath).get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['latitude'], equals(10.123456));
        expect((snap.value as Map)['allowedRadiusMeters'], equals(200.0));
      });

      test('watchStoreGpsConfig() streams config and handles empty node defaults', () async {
        final storeRef = mockDb.getOrCreateRef(storeGpsPath);
        final stream = dataSource.watchStoreGpsConfig(storeId);
        final emissions = <StoreGpsConfigModel?>[];
        final sub = stream.listen(emissions.add);

        storeRef.emitValue({
          'latitude': 10.5,
          'longitude': 105.5,
          'allowedRadiusMeters': 250.0,
        });

        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(1));
        expect(emissions.first?.latitude, equals(10.5));
        expect(emissions.first?.allowedRadiusMeters, equals(250.0));

        await sub.cancel();
      });

      test('DefaultLocationService simulation and fallback', () async {
        // Default position before simulation
        final defaultPos = await locationService.getCurrentPosition();
        expect(defaultPos, isNotNull);
        expect(defaultPos!.latitude, equals(10.035));
        expect(locationService.isSimulated, isFalse);

        // Set simulated coordinate
        locationService.setSimulatedPosition(const GeoPoint(10.999, 105.999, 'Vị trí thử nghiệm'));
        expect(locationService.isSimulated, isTrue);

        final simPos = await locationService.getCurrentPosition();
        expect(simPos!.latitude, equals(10.999));
        expect(simPos.longitude, equals(105.999));
        expect(simPos.label, equals('Vị trí thử nghiệm'));

        // Reset simulation
        locationService.setSimulatedPosition(null);
        expect(locationService.isSimulated, isFalse);
      });
    });
  });
}
