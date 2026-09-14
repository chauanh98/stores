import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/store_resolver_helper.dart';
import 'package:stores/domain/entities/user_account.dart';

void main() {
  group('StoreResolverHelper Adversarial Stress Tests', () {
    // =========================================================================
    // 1. normalizeStoreId: Exhaustive Permutations & Boundary Cases
    // =========================================================================
    group('1. normalizeStoreId: Permutations & Edge Cases', () {
      test('Null, empty, whitespace variations return empty string', () {
        expect(StoreResolverHelper.normalizeStoreId(null), equals(''));
        expect(StoreResolverHelper.normalizeStoreId(''), equals(''));
        expect(StoreResolverHelper.normalizeStoreId(' '), equals(''));
        expect(StoreResolverHelper.normalizeStoreId('   '), equals(''));
        expect(StoreResolverHelper.normalizeStoreId('\t'), equals(''));
        expect(StoreResolverHelper.normalizeStoreId('\n'), equals(''));
        expect(StoreResolverHelper.normalizeStoreId(' \t \n \r '), equals(''));
      });

      test('Canonical IDs (case-insensitive & padded)', () {
        expect(StoreResolverHelper.normalizeStoreId('store_001'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('STORE_001'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('Store_001'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('  store_001  '), equals('store_001'));

        expect(StoreResolverHelper.normalizeStoreId('store_002'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('STORE_002'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('Store_002'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('\tstore_002\n'), equals('store_002'));
      });

      test('Legacy branch aliases (case-insensitive & padded)', () {
        expect(StoreResolverHelper.normalizeStoreId('branch_1'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('BRANCH_1'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('Branch_1'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('  branch_1  '), equals('store_001'));

        expect(StoreResolverHelper.normalizeStoreId('branch_2'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('BRANCH_2'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('Branch_2'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('  branch_2\t'), equals('store_002'));
      });

      test('Short codes: ĐT, đt, DT, dt, TB, tb, Tb, tB', () {
        final dtVariations = ['ĐT', 'đt', 'Đt', 'đT', 'DT', 'dt', 'Dt', 'dT', '  ĐT  ', '\tdt\n'];
        for (final v in dtVariations) {
          expect(StoreResolverHelper.normalizeStoreId(v), equals('store_001'),
              reason: 'Failed for variation: $v');
        }

        final tbVariations = ['TB', 'tb', 'Tb', 'tB', '  TB  ', '\ttb\n'];
        for (final v in tbVariations) {
          expect(StoreResolverHelper.normalizeStoreId(v), equals('store_002'),
              reason: 'Failed for variation: $v');
        }
      });

      test('Vietnamese names with diacritics (all cases and prefixes)', () {
        final dtAccented = [
          'đông thắng',
          'Đông Thắng',
          'ĐÔNG THẮNG',
          'đÔng ThẮng',
          'Chi nhánh Đông Thắng',
          'CHI NHÁNH ĐÔNG THẮNG',
          'chi nhánh đông thắng',
          'CN Đông Thắng',
          'Cửa hàng Đông Thắng',
          '  Đông Thắng  ',
        ];
        for (final name in dtAccented) {
          expect(StoreResolverHelper.normalizeStoreId(name), equals('store_001'),
              reason: 'Failed for: $name');
        }

        final tbAccented = [
          'thới bình',
          'Thới Bình',
          'THỚI BÌNH',
          'thời bình', // Common diacritic typo in real data
          'Thời Bình',
          'THỜI BÌNH',
          'Chi nhánh Thới Bình',
          'Chi nhánh Thời Bình',
          'CHI NHÁNH THỚI BÌNH',
          'CHI NHÁNH THỜI BÌNH',
          'CN Thới Bình',
          'CN Thời Bình',
          '  Thới Bình  ',
          '  Thời Bình  ',
        ];
        for (final name in tbAccented) {
          expect(StoreResolverHelper.normalizeStoreId(name), equals('store_002'),
              reason: 'Failed for: $name');
        }
      });

      test('Vietnamese names without diacritics (unaccented)', () {
        final dtUnaccented = [
          'dong thang',
          'Dong Thang',
          'DONG THANG',
          'dongthang',
          'DONGTHANG',
          'Chi nhanh Dong Thang',
          '  Dong Thang  ',
        ];
        for (final name in dtUnaccented) {
          expect(StoreResolverHelper.normalizeStoreId(name), equals('store_001'),
              reason: 'Failed for unaccented: $name');
        }

        final tbUnaccented = [
          'thoi binh',
          'Thoi Binh',
          'THOI BINH',
          'thoibinh',
          'THOIBINH',
          'Chi nhanh Thoi Binh',
          '  Thoi Binh  ',
        ];
        for (final name in tbUnaccented) {
          expect(StoreResolverHelper.normalizeStoreId(name), equals('store_002'),
              reason: 'Failed for unaccented: $name');
        }
      });

      test('Unknown and custom store IDs are preserved (trimmed)', () {
        expect(StoreResolverHelper.normalizeStoreId('store_003'), equals('store_003'));
        expect(StoreResolverHelper.normalizeStoreId('store_999'), equals('store_999'));
        expect(StoreResolverHelper.normalizeStoreId('branch_3'), equals('branch_3'));
        expect(StoreResolverHelper.normalizeStoreId('custom_warehouse_hn'), equals('custom_warehouse_hn'));
        expect(StoreResolverHelper.normalizeStoreId('  store_xyz  '), equals('store_xyz'));
      });
    });

    // =========================================================================
    // 2. resolveTargetStoreIds: Exhaustive Permutations & Fallbacks
    // =========================================================================
    group('2. resolveTargetStoreIds: Permutations & Collections', () {
      test('Empty list fallback returns canonical stores', () {
        final result = StoreResolverHelper.resolveTargetStoreIds([]);
        expect(result, containsAll(['store_001', 'store_002']));
        expect(result.length, equals(2));
      });

      test('List with only blank/whitespace strings fallback returns canonical stores', () {
        final result1 = StoreResolverHelper.resolveTargetStoreIds(['', '   ', '\t']);
        expect(result1, containsAll(['store_001', 'store_002']));
        expect(result1.length, equals(2));
      });

      test('Single branch selections', () {
        expect(StoreResolverHelper.resolveTargetStoreIds(['store_001']), equals(['store_001']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['store_002']), equals(['store_002']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['branch_1']), equals(['store_001']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['branch_2']), equals(['store_002']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['ĐT']), equals(['store_001']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['TB']), equals(['store_002']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['Đông Thắng']), equals(['store_001']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['Dong Thang']), equals(['store_001']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['Thới Bình']), equals(['store_002']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['Thời Bình']), equals(['store_002']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['Thoi Binh']), equals(['store_002']));
      });

      test('Both stores in all alias combinations', () {
        final aliasPairs = [
          ['store_001', 'store_002'],
          ['branch_1', 'branch_2'],
          ['BRANCH_1', 'BRANCH_2'],
          ['ĐT', 'TB'],
          ['dt', 'tb'],
          ['Đông Thắng', 'Thới Bình'],
          ['Đông Thắng', 'Thời Bình'],
          ['Dong Thang', 'Thoi Binh'],
          ['store_001', 'branch_2'],
          ['branch_1', 'store_002'],
          ['ĐT', 'Thới Bình'],
          ['Đông Thắng', 'TB'],
        ];

        for (final pair in aliasPairs) {
          final result = StoreResolverHelper.resolveTargetStoreIds(pair);
          expect(result, containsAll(['store_001', 'store_002']),
              reason: 'Failed for pair: $pair');
          expect(result.length, equals(2));
        }
      });

      test('Duplicate representations deduplicate accurately to single or two stores', () {
        // Redundant store 1 representations
        final store1Duplicates = [
          'store_001',
          'STORE_001',
          'branch_1',
          'BRANCH_1',
          'ĐT',
          'đt',
          'dt',
          'Đông Thắng',
          'dong thang',
          'dongthang',
          'Chi nhánh Đông Thắng'
        ];
        final result1 = StoreResolverHelper.resolveTargetStoreIds(store1Duplicates);
        expect(result1, equals(['store_001']));

        // Redundant store 2 representations
        final store2Duplicates = [
          'store_002',
          'STORE_002',
          'branch_2',
          'BRANCH_2',
          'TB',
          'tb',
          'Thới Bình',
          'Thời Bình',
          'thoi binh',
          'thoibinh',
          'Chi nhánh Thới Bình'
        ];
        final result2 = StoreResolverHelper.resolveTargetStoreIds(store2Duplicates);
        expect(result2, equals(['store_002']));

        // Mixed redundant representations
        final mixed = [...store1Duplicates, ...store2Duplicates];
        final resultMixed = StoreResolverHelper.resolveTargetStoreIds(mixed);
        expect(resultMixed, containsAll(['store_001', 'store_002']));
        expect(resultMixed.length, equals(2));
      });

      test('Unknown store IDs are preserved in resolved list', () {
        final result = StoreResolverHelper.resolveTargetStoreIds(['store_999']);
        expect(result, equals(['store_999']));

        final mixedResult = StoreResolverHelper.resolveTargetStoreIds(['store_001', 'store_999']);
        expect(mixedResult, containsAll(['store_001', 'store_999']));
        expect(mixedResult.length, equals(2));

        final aliasAndCustom = StoreResolverHelper.resolveTargetStoreIds(['branch_1', 'branch_2', 'custom_wh']);
        expect(aliasAndCustom, containsAll(['store_001', 'store_002', 'custom_wh']));
        expect(aliasAndCustom.length, equals(3));
      });
    });

    // =========================================================================
    // 3. User Roles, Permissions & Filter Overrides
    // =========================================================================
    group('3. User Roles, Permissions & Filter Overrides', () {
      test('Staff (nhanvien) is locked to assigned store regardless of selectedBranches', () {
        const staffDT = UserAccount(
          username: 'nhanvien_dt',
          displayName: 'Nhân viên Đông Thắng',
          role: 'nhanvien',
          storeId: 'store_001',
        );

        // Even if selectedBranches has both stores, staff is restricted
        final resDT = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001', 'store_002'],
          user: staffDT,
        );
        expect(resDT, equals(['store_001']));

        const staffTB = UserAccount(
          username: 'nhanvien_tb',
          displayName: 'Nhân viên Thới Bình',
          role: 'nhanvien',
          storeId: 'store_002',
        );

        final resTB = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001'],
          user: staffTB,
        );
        expect(resTB, equals(['store_002']));
      });

      test('Staff with legacy alias in storeId is normalized', () {
        const staffAlias = UserAccount(
          username: 'nhanvien_alias',
          displayName: 'Nhân viên Alias',
          role: 'nhanvien',
          storeId: 'branch_2',
        );

        final res = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001', 'store_002'],
          user: staffAlias,
        );
        expect(res, equals(['store_002']));
      });

      test('Staff with empty storeId falls back to currentStoreId or default', () {
        const staffEmpty = UserAccount(
          username: 'nhanvien_empty',
          displayName: 'Nhân viên',
          role: 'nhanvien',
          storeId: '',
        );

        final res1 = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001', 'store_002'],
          user: staffEmpty,
          currentStoreId: 'store_002',
        );
        expect(res1, equals(['store_002']));

        final res2 = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001', 'store_002'],
          user: staffEmpty,
          currentStoreId: '',
        );
        expect(res2, equals(['store_001']));
      });

      test('Admin and Supervisor can switch stores and view selected branches', () {
        const admin = UserAccount(
          username: 'admin_user',
          displayName: 'Admin User',
          role: 'admin',
          storeId: 'store_001',
        );

        expect(
          StoreResolverHelper.resolveTargetStoreIds(['store_001'], user: admin),
          equals(['store_001']),
        );
        expect(
          StoreResolverHelper.resolveTargetStoreIds(['store_002'], user: admin),
          equals(['store_002']),
        );
        expect(
          StoreResolverHelper.resolveTargetStoreIds(['branch_1', 'branch_2'], user: admin),
          containsAll(['store_001', 'store_002']),
        );

        const supervisor = UserAccount(
          username: 'sup_user',
          displayName: 'Supervisor User',
          role: 'supervisor',
          storeId: 'store_002',
        );

        expect(
          StoreResolverHelper.resolveTargetStoreIds(['store_001', 'store_002'], user: supervisor),
          containsAll(['store_001', 'store_002']),
        );
      });

      test('storeFilter parameter: "all", single store, and alias overrides', () {
        // storeFilter == 'all'
        final allRes = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001'],
          storeFilter: 'all',
        );
        expect(allRes, containsAll(['store_001', 'store_002']));

        // storeFilter == 'store_002' overrides selectedBranches
        final singleRes = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001'],
          storeFilter: 'store_002',
        );
        expect(singleRes, equals(['store_002']));

        // storeFilter with alias 'branch_1'
        final aliasRes = StoreResolverHelper.resolveTargetStoreIds(
          ['store_002'],
          storeFilter: 'branch_1',
        );
        expect(aliasRes, equals(['store_001']));

        // storeFilter with Vietnamese name 'Thời Bình'
        final nameRes = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001'],
          storeFilter: 'Thời Bình',
        );
        expect(nameRes, equals(['store_002']));
      });

      test('Fallback priority when selectedBranches is empty: availableStoreIds -> availableStores -> currentStoreId -> default', () {
        // availableStoreIds
        final resIds = StoreResolverHelper.resolveTargetStoreIds(
          [],
          availableStoreIds: ['store_001', 'store_002', 'store_003'],
        );
        expect(resIds, containsAll(['store_001', 'store_002', 'store_003']));
        expect(resIds.length, equals(3));

        // availableStores Map
        final resMap = StoreResolverHelper.resolveTargetStoreIds(
          [],
          availableStores: {'store_001': 'Đông Thắng', 'store_002': 'Thới Bình'},
        );
        expect(resMap, containsAll(['store_001', 'store_002']));

        // currentStoreId
        final resCurrent = StoreResolverHelper.resolveTargetStoreIds(
          [],
          currentStoreId: 'store_002',
        );
        expect(resCurrent, equals(['store_002']));
      });
    });
  });
}
