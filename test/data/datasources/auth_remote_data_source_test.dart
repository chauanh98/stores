import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:stores/data/datasources/firebase/auth_remote_data_source.dart';

import '../../support/firebase_test_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthRemoteDataSource', () {
    late MockFirebaseDatabase mockDb;
    late AuthRemoteDataSource dataSource;
    const accountsPath = 'stores/accounts';

    setUp(() {
      mockDb = MockFirebaseDatabase();
      dataSource = AuthRemoteDataSource(mockDb);
    });

    group('watchAllAccounts() - Reactivity & Username Injection', () {
      test('No double fetch: .get() is NEVER called when subscribing to watchAllAccounts()', () async {
        final ref = mockDb.getOrCreateRef(accountsPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = dataSource.watchAllAccounts().listen(emissions.add);

        ref.emitChildAdded('staff_1', {
          'displayName': 'Staff One',
          'role': 'nhanvien',
          'storeId': 'store_001',
        });

        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        expect(mockDb.wasGetCalled(accountsPath), isFalse);
        expect(mockDb.getCallCount(accountsPath), equals(0));

        await sub.cancel();
      });

      test('Username injection from snapshot.key: populates username field even if missing in value', () async {
        final ref = mockDb.getOrCreateRef(accountsPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = dataSource.watchAllAccounts().listen(emissions.add);

        // Map has NO username key
        ref.emitChildAdded('admin_special', {
          'displayName': 'Special Admin',
          'role': 'admin',
          'storeId': 'store_001',
        });

        await Future.delayed(const Duration(milliseconds: 65));

        expect(emissions.length, equals(1));
        final account = emissions.first.first;
        expect(account['username'], equals('admin_special'));
        expect(account['displayName'], equals('Special Admin'));

        await sub.cancel();
      });

      test('Debounce grouping: rapid burst of accounts coalesces into single emission', () async {
        final ref = mockDb.getOrCreateRef(accountsPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = dataSource.watchAllAccounts().listen(emissions.add);

        for (int i = 1; i <= 15; i++) {
          ref.emitChildAdded('user_$i', {
            'displayName': 'User $i',
            'role': 'nhanvien',
            'storeId': 'store_001',
          });
        }

        await Future.delayed(const Duration(milliseconds: 20));
        expect(emissions, isEmpty);

        await Future.delayed(const Duration(milliseconds: 55));
        expect(emissions.length, equals(1));
        expect(emissions.first.length, equals(15));
        expect(emissions.first.map((u) => u['username']), containsAll(['user_1', 'user_15']));

        await sub.cancel();
      });

      test('emptyCheckSub: empty accounts node emits [] without hanging', () async {
        final ref = mockDb.getOrCreateRef(accountsPath);
        final completer = Completer<List<Map<String, dynamic>>>();
        final sub = dataSource.watchAllAccounts().listen((data) {
          if (!completer.isCompleted) completer.complete(data);
        });

        ref.emitNullValue();

        final result = await completer.future.timeout(const Duration(milliseconds: 150));
        expect(result, isEmpty);

        await sub.cancel();
      });

      test('Immediate emit on childChanged with username re-injected', () async {
        final ref = mockDb.getOrCreateRef(accountsPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = dataSource.watchAllAccounts().listen(emissions.add);

        ref.emitChildAdded('user_up', {'displayName': 'Old Name', 'role': 'nhanvien'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.length, equals(1));

        final stopwatch = Stopwatch()..start();
        ref.emitChildChanged('user_up', {'displayName': 'New Name', 'role': 'supervisor'});
        await Future.delayed(const Duration(milliseconds: 10));
        stopwatch.stop();

        expect(emissions.length, equals(2));
        expect(emissions.last.first['username'], equals('user_up'));
        expect(emissions.last.first['displayName'], equals('New Name'));
        expect(emissions.last.first['role'], equals('supervisor'));
        expect(stopwatch.elapsedMilliseconds, lessThan(40));

        await sub.cancel();
      });

      test('Immediate emit on childRemoved: purges account from cache', () async {
        final ref = mockDb.getOrCreateRef(accountsPath);
        final emissions = <List<Map<String, dynamic>>>[];
        final sub = dataSource.watchAllAccounts().listen(emissions.add);

        ref.emitChildAdded('u1', {'displayName': 'U1'});
        ref.emitChildAdded('u2', {'displayName': 'U2'});
        await Future.delayed(const Duration(milliseconds: 65));
        expect(emissions.first.length, equals(2));

        ref.emitChildRemoved('u1');
        await Future.delayed(const Duration(milliseconds: 10));

        expect(emissions.length, equals(2));
        expect(emissions.last.length, equals(1));
        expect(emissions.last.first['username'], equals('u2'));

        await sub.cancel();
      });

      test('Stream cancellation cleans up all listeners', () async {
        final ref = mockDb.getOrCreateRef(accountsPath);
        final sub = dataSource.watchAllAccounts().listen((_) {});

        expect(ref.childAddedStream.activeListeners, equals(1));
        expect(ref.childChangedStream.activeListeners, equals(1));
        expect(ref.childRemovedStream.activeListeners, equals(1));
        expect(ref.valueStream.activeListeners, equals(1));

        await sub.cancel();

        expect(ref.childAddedStream.activeListeners, equals(0));
        expect(ref.childChangedStream.activeListeners, equals(0));
        expect(ref.childRemovedStream.activeListeners, equals(0));
        expect(ref.valueStream.activeListeners, equals(0));
      });
    });

    group('login() Operations & Authentication', () {
      test('valid username and password returns populated UserAccount', () async {
        mockDb.seedData(accountsPath, {
          'admin1': {
            'displayName': 'Store Admin',
            'role': 'admin',
            'storeId': 'store_001',
            'password': 'secret_password_123',
          },
        });

        final user = await dataSource.login('admin1', 'secret_password_123');
        expect(user, isNotNull);
        expect(user!.username, equals('admin1'));
        expect(user.displayName, equals('Store Admin'));
        expect(user.role, equals('admin'));
        expect(user.isAdmin, isTrue);
        expect(user.storeId, equals('store_001'));
      });

      test('trims whitespace from username before querying', () async {
        mockDb.seedData(accountsPath, {
          'supervisor1': {
            'displayName': 'Store Supervisor',
            'role': 'supervisor',
            'storeId': 'store_002',
            'password': 'pass',
          },
        });

        final user = await dataSource.login('  supervisor1  ', 'pass');
        expect(user, isNotNull);
        expect(user!.username, equals('supervisor1'));
        expect(user.isSupervisor, isTrue);
      });

      test('incorrect password returns null', () async {
        mockDb.seedData(accountsPath, {
          'user1': {
            'password': 'correct_pass',
            'role': 'nhanvien',
          },
        });

        final user = await dataSource.login('user1', 'wrong_pass');
        expect(user, isNull);
      });

      test('non-existent account returns null', () async {
        final user = await dataSource.login('ghost_user', 'any_pass');
        expect(user, isNull);
      });

      test('network error or database failure throws AuthNetworkException', () async {
        mockDb.setThrowOnGet(accountsPath, true);

        expect(
          () => dataSource.login('admin1', 'pass'),
          throwsA(isA<AuthNetworkException>()),
        );
      });
    });

    group('Account Management & Password Updates', () {
      test('saveAccount() creates or updates account data', () async {
        await dataSource.saveAccount('staff_new', {
          'displayName': 'New Staff',
          'role': 'nhanvien',
          'storeId': 'store_001',
          'password': 'staff_pwd',
        });

        final snap = await mockDb.getOrCreateRef(accountsPath).child('staff_new').get();
        expect(snap.exists, isTrue);
        expect((snap.value as Map)['displayName'], equals('New Staff'));
      });

      test('deleteAccount() removes account from database', () async {
        mockDb.seedData(accountsPath, {
          'obsolete_user': {'displayName': 'Obsolete'},
        });

        await dataSource.deleteAccount('obsolete_user');

        final snap = await mockDb.getOrCreateRef(accountsPath).child('obsolete_user').get();
        expect(snap.exists, isFalse);
      });

      test('getAccountPassword() returns current password string', () async {
        mockDb.seedData(accountsPath, {
          'user_pw': {
            'displayName': 'User PW',
            'password': 'my_super_secret',
          },
        });

        final pass = await dataSource.getAccountPassword('user_pw');
        expect(pass, equals('my_super_secret'));

        final missingPass = await dataSource.getAccountPassword('no_such_user');
        expect(missingPass, isNull);
      });

      test('updatePassword() succeeds when old password matches', () async {
        mockDb.seedData(accountsPath, {
          'user_change': {
            'password': 'old_password',
          },
        });

        await dataSource.updatePassword('user_change', 'old_password', 'brand_new_password');

        final newPass = await dataSource.getAccountPassword('user_change');
        expect(newPass, equals('brand_new_password'));
      });

      test('updatePassword() throws Exception when old password does not match', () async {
        mockDb.seedData(accountsPath, {
          'user_change': {
            'password': 'real_password',
          },
        });

        expect(
          () => dataSource.updatePassword('user_change', 'wrong_old_password', 'new_pass'),
          throwsA(
            predicate((e) => e is Exception && e.toString().contains('Mật khẩu hiện tại không chính xác')),
          ),
        );
      });
    });
  });
}
