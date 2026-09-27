import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/attendance/attendance_providers.dart';
import 'package:stores/application/attendance/store_gps_config_notifier.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/data/datasources/firebase/attendance_remote_data_source.dart';
import 'package:stores/domain/attendance/geo_distance_helper.dart';
import 'package:stores/domain/attendance/store_gps_config.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'fake_attendance_repository.dart';

/// Controllable attendance repository providing Completers and error triggers
/// to simulate asynchronous in-flight requests and network failures.
class ControllableAttendanceRepository extends FakeAttendanceRepository {
  Completer<StoreGpsConfig?>? getGpsCompleter;
  Completer<void>? saveGpsCompleter;
  bool shouldThrowOnGet = false;
  bool shouldThrowOnSave = false;
  String errorMessage = 'Simulated network exception';

  @override
  Future<StoreGpsConfig?> getStoreGpsConfig(String storeId) async {
    if (shouldThrowOnGet) {
      throw Exception(errorMessage);
    }
    if (getGpsCompleter != null) {
      return getGpsCompleter!.future;
    }
    return super.getStoreGpsConfig(storeId);
  }

  @override
  Future<void> saveStoreGpsConfig(StoreGpsConfig config) async {
    if (shouldThrowOnSave) {
      throw Exception(errorMessage);
    }
    if (saveGpsCompleter != null) {
      return saveGpsCompleter!.future;
    }
    return super.saveStoreGpsConfig(config);
  }
}

class _TestAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _TestAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StoreGpsConfigState Tests', () {
    test('State copyWith maintains or overwrites all fields correctly', () {
      const initial = StoreGpsConfigState(
        storeId: 'store_init',
        isLoading: true,
        isSaving: false,
      );

      final updated = initial.copyWith(
        storeId: 'store_updated',
        isLoading: false,
        isSaving: true,
        errorMessage: 'Some error',
        successMessage: 'Some success',
        config: const StoreGpsConfig(
          storeId: 'store_updated',
          latitude: 10.5,
          longitude: 106.5,
        ),
      );

      expect(updated.storeId, 'store_updated');
      expect(updated.isLoading, isFalse);
      expect(updated.isSaving, isTrue);
      expect(updated.errorMessage, 'Some error');
      expect(updated.successMessage, 'Some success');
      expect(updated.config?.latitude, 10.5);
      expect(updated.config?.longitude, 106.5);

      // copyWith without args preserves previous fields (except error/success which default null in copyWith)
      final preserved = updated.copyWith();
      expect(preserved.storeId, 'store_updated');
      expect(preserved.isLoading, isFalse);
      expect(preserved.isSaving, isTrue);
      expect(preserved.config?.storeId, 'store_updated');
    });
  });

  group('StoreGpsConfigNotifier - Normal Operations', () {
    late ControllableAttendanceRepository repo;
    late FakeLocationService locationService;

    const sampleConfig = StoreGpsConfig(
      storeId: 'store_001',
      latitude: 10.035000,
      longitude: 105.788000,
      allowedRadiusMeters: 120.0,
      storeName: 'Chi nhánh Đông Thắng',
    );

    setUp(() {
      repo = ControllableAttendanceRepository();
      locationService = FakeLocationService();
    });

    test('Initializes state and loads existing store GPS config successfully', () async {
      repo.storeConfigs['store_001'] = sampleConfig;

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_001',
      );

      // Initially loading
      expect(notifier.state.storeId, 'store_001');

      // Wait for microtask / async loadConfig to finish
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.config, isNotNull);
      expect(notifier.state.config?.storeId, 'store_001');
      expect(notifier.state.config?.latitude, 10.035000);
      expect(notifier.state.config?.longitude, 105.788000);
      expect(notifier.state.config?.allowedRadiusMeters, 120.0);
    });

    test('Falls back to default coordinates when repository returns null config', () async {
      repo.storeConfigs.clear(); // Ensure repository returns null

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_new',
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.errorMessage, isNull);
      expect(notifier.state.config, isNotNull);
      expect(notifier.state.config?.storeId, 'store_new');
      expect(notifier.state.config?.latitude, 10.035000);
      expect(notifier.state.config?.longitude, 105.788000);
      expect(
        notifier.state.config?.allowedRadiusMeters,
        GeoDistanceHelper.defaultAllowedRadiusMeters,
      );
    });

    test('Sets errorMessage and isLoading: false when loadConfig throws error', () async {
      repo.shouldThrowOnGet = true;
      repo.errorMessage = 'Mất kết nối máy chủ Firebase';

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_001',
      );

      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(notifier.state.isLoading, isFalse);
      expect(notifier.state.config, isNull);
      expect(notifier.state.errorMessage, contains('Mất kết nối máy chủ Firebase'));
    });

    test('loadConfig can be called again for a different storeId', () async {
      const config2 = StoreGpsConfig(
        storeId: 'store_002',
        latitude: 10.123000,
        longitude: 105.654000,
        allowedRadiusMeters: 200.0,
      );
      repo.storeConfigs['store_002'] = config2;

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_001',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Switch to store_002
      await notifier.loadConfig('store_002');

      expect(notifier.state.storeId, 'store_002');
      expect(notifier.state.config?.storeId, 'store_002');
      expect(notifier.state.config?.latitude, 10.123000);
      expect(notifier.state.config?.allowedRadiusMeters, 200.0);
    });

    test('saveConfig saves to repository, updates state, and returns true on success', () async {
      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_001',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      const updatedConfig = StoreGpsConfig(
        storeId: 'store_001',
        latitude: 10.999999,
        longitude: 106.888888,
        allowedRadiusMeters: 300.0,
        storeName: 'Chi nhánh Cập Nhật',
      );

      final success = await notifier.saveConfig(updatedConfig);

      expect(success, isTrue);
      expect(notifier.state.isSaving, isFalse);
      expect(notifier.state.errorMessage, isNull);
      expect(
        notifier.state.successMessage,
        'Lưu cấu hình GPS chi nhánh thành công!',
      );
      expect(notifier.state.config?.latitude, 10.999999);
      expect(notifier.state.config?.allowedRadiusMeters, 300.0);
      expect(repo.storeConfigs['store_001']?.latitude, 10.999999);
    });

    test('saveConfig sets errorMessage, isSaving: false, and returns false on failure', () async {
      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_001',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      repo.shouldThrowOnSave = true;
      repo.errorMessage = 'Permission denied on Realtime DB';

      const configToSave = StoreGpsConfig(
        storeId: 'store_001',
        latitude: 10.5,
        longitude: 105.5,
      );

      final success = await notifier.saveConfig(configToSave);

      expect(success, isFalse);
      expect(notifier.state.isSaving, isFalse);
      expect(notifier.state.errorMessage, contains('Permission denied on Realtime DB'));
      expect(notifier.state.successMessage, isNull);
    });

    test('getCurrentGpsCoordinates fetches current coordinates from LocationService', () async {
      const mockPos = GeoPoint(10.7769, 106.7009, 'Test GPS');
      locationService.setSimulatedPosition(mockPos);

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_001',
      );

      final coords = await notifier.getCurrentGpsCoordinates();

      expect(coords, isNotNull);
      expect(coords?.latitude, 10.7769);
      expect(coords?.longitude, 106.7009);
    });

    test('getCurrentGpsCoordinates returns null when LocationService position is null', () async {
      locationService.setSimulatedPosition(null);

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_001',
      );

      final coords = await notifier.getCurrentGpsCoordinates();
      expect(coords, isNull);
    });
  });

  group('StoreGpsConfigNotifier - Dispose Safety Simulation (R3 Guardrails)', () {
    late ControllableAttendanceRepository repo;
    late FakeLocationService locationService;

    const testConfig = StoreGpsConfig(
      storeId: 'store_stress',
      latitude: 10.8231,
      longitude: 106.6297,
      allowedRadiusMeters: 250.0,
      storeName: 'Chi nhánh Tân Bình',
    );

    setUp(() {
      repo = ControllableAttendanceRepository();
      locationService = FakeLocationService();
    });

    test('Constructor loadConfig pending -> dispose notifier -> complete Future -> NO exception thrown', () async {
      // 1. Setup pending completer before creating notifier
      final getCompleter = Completer<StoreGpsConfig?>();
      repo.getGpsCompleter = getCompleter;

      // 2. Notifier calls loadConfig in constructor which awaits getCompleter.future
      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress',
      );
      expect(notifier.mounted, isTrue);
      expect(notifier.state.isLoading, isTrue);

      // 3. User navigates away rapidly: notifier disposed while request is in flight
      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // 4. Firebase returns response after page was popped
      getCompleter.complete(testConfig);

      // 5. Allow microtasks/event loop to process async completion
      await Future<void>.delayed(const Duration(milliseconds: 20));

      // 6. Verify NO StateError was thrown and state was safely untouched
      expect(notifier.mounted, isFalse);
    });

    test('Constructor loadConfig pending -> dispose notifier -> complete Future with error -> NO exception thrown', () async {
      final getCompleter = Completer<StoreGpsConfig?>();
      repo.getGpsCompleter = getCompleter;

      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress',
      );
      expect(notifier.mounted, isTrue);

      // Disposed during in-flight network call
      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // Network socket timeout or Firebase error triggers catch block
      getCompleter.completeError(TimeoutException('Connection timed out'));

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // No unhandled exception should escape
      expect(notifier.mounted, isFalse);
    });

    test('Explicit loadConfig pending -> dispose notifier -> complete Future -> NO exception thrown', () async {
      // Let initial constructor load complete normally first
      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(notifier.mounted, isTrue);

      // Now set up in-flight completer for a secondary loadConfig call
      final reloadCompleter = Completer<StoreGpsConfig?>();
      repo.getGpsCompleter = reloadCompleter;

      // Trigger loadConfig without awaiting it immediately
      final loadFuture = notifier.loadConfig('store_stress_2');

      // Dispose while request is in flight
      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // Network completes
      reloadCompleter.complete(testConfig);
      await loadFuture;

      expect(notifier.mounted, isFalse);
    });

    test('Explicit loadConfig pending -> dispose notifier -> complete with error -> NO exception thrown', () async {
      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final reloadCompleter = Completer<StoreGpsConfig?>();
      repo.getGpsCompleter = reloadCompleter;

      final loadFuture = notifier.loadConfig('store_stress_2');

      // Dispose while pending
      notifier.dispose();

      // Complete with error
      reloadCompleter.completeError(Exception('Firebase permission denied'));
      await loadFuture;

      expect(notifier.mounted, isFalse);
    });

    test('saveConfig pending -> dispose notifier -> complete Future -> returns false, NO exception thrown', () async {
      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      // Setup in-flight save completer
      final saveCompleter = Completer<void>();
      repo.saveGpsCompleter = saveCompleter;

      // Start saving
      final saveFuture = notifier.saveConfig(testConfig);
      expect(notifier.state.isSaving, isTrue);

      // User hits back button while save is committing to Firebase
      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // Firebase commit finishes
      saveCompleter.complete();
      final result = await saveFuture;

      // Method safely returns false because notifier is no longer mounted
      expect(result, isFalse);
      expect(notifier.mounted, isFalse);
    });

    test('saveConfig pending -> dispose notifier -> complete with error -> returns false, NO exception thrown', () async {
      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final saveCompleter = Completer<void>();
      repo.saveGpsCompleter = saveCompleter;

      final saveFuture = notifier.saveConfig(testConfig);

      // Dispose while pending
      notifier.dispose();

      // Firebase commit fails after dispose
      saveCompleter.completeError(Exception('Network drop during write'));
      final result = await saveFuture;

      expect(result, isFalse);
      expect(notifier.mounted, isFalse);
    });

    test('Calling loadConfig on already-disposed notifier exits immediately without error', () async {
      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      notifier.dispose();
      expect(notifier.mounted, isFalse);

      // Calling loadConfig should return immediately and not touch state
      await notifier.loadConfig('store_other');
      expect(notifier.mounted, isFalse);
    });

    test('Calling saveConfig on already-disposed notifier exits immediately and returns false', () async {
      final notifier = StoreGpsConfigNotifier(
        repo,
        locationService,
        initialStoreId: 'store_stress',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      notifier.dispose();
      expect(notifier.mounted, isFalse);

      final result = await notifier.saveConfig(testConfig);
      expect(result, isFalse);
      expect(notifier.mounted, isFalse);
    });
  });

  group('StoreGpsConfigNotifier - Riverpod autoDispose Integration', () {
    late ControllableAttendanceRepository repo;
    late FakeLocationService locationService;

    setUp(() {
      repo = ControllableAttendanceRepository();
      locationService = FakeLocationService();
    });

    test('storeGpsConfigNotifierProvider auto-disposes cleanly without crash during in-flight load', () async {
      final getCompleter = Completer<StoreGpsConfig?>();
      repo.getGpsCompleter = getCompleter;

      final container = ProviderContainer(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(locationService),
          currentStoreIdProvider.overrideWithValue('store_auto_1'),
          authProvider.overrideWith(
            (ref) => _TestAuthNotifier(
              const UserAccount(
                username: 'staff_1',
                displayName: 'Nhân viên',
                role: 'staff',
                storeId: 'store_auto_1',
              ),
            ),
          ),
        ],
      );

      // Read notifier through subscription to simulate active widget
      final sub = container.listen(
        storeGpsConfigNotifierProvider,
        (previous, next) {},
      );

      final notifier = container.read(storeGpsConfigNotifierProvider.notifier);
      expect(notifier.mounted, isTrue);

      // Simulate widget unmount: close subscription and dispose container
      sub.close();
      container.dispose();

      // Complete in-flight Firebase response after container and notifier disposal
      getCompleter.complete(
        const StoreGpsConfig(
          storeId: 'store_auto_1',
          latitude: 10.1,
          longitude: 106.1,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      // If dispose safety was missing, container.dispose() + completing completer would throw StateError
      expect(notifier.mounted, isFalse);
    });

    test('storeGpsConfigNotifierProvider selects effective storeId based on user role', () async {
      // Test admin user: uses currentStoreIdProvider
      final adminContainer = ProviderContainer(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(locationService),
          currentStoreIdProvider.overrideWithValue('store_admin_selected'),
          authProvider.overrideWith(
            (ref) => _TestAuthNotifier(
              const UserAccount(
                username: 'admin_user',
                displayName: 'Admin User',
                role: 'admin',
                storeId: 'store_default',
              ),
            ),
          ),
        ],
      );

      final adminNotifier = adminContainer.read(storeGpsConfigNotifierProvider.notifier);
      expect(adminNotifier.state.storeId, 'store_admin_selected');
      adminContainer.dispose();

      // Test staff user with specific storeId: uses user.storeId
      final staffContainer = ProviderContainer(
        overrides: [
          attendanceRepositoryProvider.overrideWithValue(repo),
          locationServiceProvider.overrideWithValue(locationService),
          currentStoreIdProvider.overrideWithValue('store_global'),
          authProvider.overrideWith(
            (ref) => _TestAuthNotifier(
              const UserAccount(
                username: 'staff_user',
                displayName: 'Staff User',
                role: 'nhanvien',
                storeId: 'store_staff_assigned',
              ),
            ),
          ),
        ],
      );

      final staffNotifier = staffContainer.read(storeGpsConfigNotifierProvider.notifier);
      expect(staffNotifier.state.storeId, 'store_staff_assigned');
      staffContainer.dispose();
    });
  });
}
