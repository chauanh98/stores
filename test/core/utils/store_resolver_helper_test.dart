import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/utils/store_resolver_helper.dart';
import 'package:stores/domain/entities/user_account.dart';

void main() {
  group('StoreResolverHelper Unit Tests', () {
    // -------------------------------------------------------------------------
    // 1. normalizeStoreId
    // -------------------------------------------------------------------------
    group('1. normalizeStoreId normalization', () {
      test('Normalizes canonical IDs accurately', () {
        expect(StoreResolverHelper.normalizeStoreId('store_001'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('store_002'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('STORE_001'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('STORE_002'), equals('store_002'));
      });

      test('Normalizes legacy branch aliases accurately', () {
        expect(StoreResolverHelper.normalizeStoreId('branch_1'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('branch_2'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('BRANCH_1'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('BRANCH_2'), equals('store_002'));
      });

      test('Normalizes short codes accurately', () {
        expect(StoreResolverHelper.normalizeStoreId('ĐT'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('đt'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('dt'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('DT'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('TB'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('tb'), equals('store_002'));
      });

      test('Normalizes Vietnamese store names and unaccented variations', () {
        expect(StoreResolverHelper.normalizeStoreId('Đông Thắng'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('Chi nhánh Đông Thắng'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('dong thang'), equals('store_001'));
        expect(StoreResolverHelper.normalizeStoreId('dongthang'), equals('store_001'));

        expect(StoreResolverHelper.normalizeStoreId('Thới Bình'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('Thời Bình'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('Chi nhánh Thới Bình'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('Chi nhánh Thời Bình'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('thoi binh'), equals('store_002'));
        expect(StoreResolverHelper.normalizeStoreId('thoibinh'), equals('store_002'));
      });

      test('Handles empty, null, whitespace, and custom IDs', () {
        expect(StoreResolverHelper.normalizeStoreId(null), equals(''));
        expect(StoreResolverHelper.normalizeStoreId(''), equals(''));
        expect(StoreResolverHelper.normalizeStoreId('   '), equals(''));
        expect(StoreResolverHelper.normalizeStoreId('custom_store_99'), equals('custom_store_99'));
      });
    });

    // -------------------------------------------------------------------------
    // 2. resolveTargetStoreIds
    // -------------------------------------------------------------------------
    group('2. resolveTargetStoreIds resolution', () {
      test('Resolves canonical IDs list', () {
        final result = StoreResolverHelper.resolveTargetStoreIds(['store_001', 'store_002']);
        expect(result, containsAll(['store_001', 'store_002']));
        expect(result.length, equals(2));
      });

      test('Resolves single canonical ID', () {
        expect(StoreResolverHelper.resolveTargetStoreIds(['store_001']), equals(['store_001']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['store_002']), equals(['store_002']));
      });

      test('Resolves legacy branch aliases', () {
        final result = StoreResolverHelper.resolveTargetStoreIds(['branch_1', 'branch_2']);
        expect(result, containsAll(['store_001', 'store_002']));
        expect(result.length, equals(2));
      });

      test('Resolves short codes and mixed identifiers', () {
        expect(StoreResolverHelper.resolveTargetStoreIds(['ĐT']), equals(['store_001']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['TB']), equals(['store_002']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['ĐT', 'TB']), containsAll(['store_001', 'store_002']));
        expect(StoreResolverHelper.resolveTargetStoreIds(['Chi nhánh Đông Thắng', 'Thới Bình']), containsAll(['store_001', 'store_002']));
      });

      test('Deduplicates duplicate branch representations', () {
        final result = StoreResolverHelper.resolveTargetStoreIds(['store_001', 'branch_1', 'ĐT', 'Đông Thắng']);
        expect(result, equals(['store_001']));
      });

      test('Fallback when empty to all available stores', () {
        final result = StoreResolverHelper.resolveTargetStoreIds([]);
        expect(result, containsAll(['store_001', 'store_002']));
        expect(result.length, equals(2));
      });

      test('Fallback when empty with explicit availableStoreIds', () {
        final result = StoreResolverHelper.resolveTargetStoreIds([], availableStoreIds: ['store_001', 'store_002', 'store_003']);
        expect(result, containsAll(['store_001', 'store_002', 'store_003']));
        expect(result.length, equals(3));
      });

      test('Fallback when empty with explicit availableStores map', () {
        final result = StoreResolverHelper.resolveTargetStoreIds([], availableStores: {
          'store_001': 'Đông Thắng',
          'store_002': 'Thới Bình',
        });
        expect(result, containsAll(['store_001', 'store_002']));
      });

      test('Explicit storeFilter == "all" returns all stores', () {
        final result = StoreResolverHelper.resolveTargetStoreIds(['store_001'], storeFilter: 'all');
        expect(result, containsAll(['store_001', 'store_002']));
        expect(result.length, equals(2));
      });

      test('Explicit storeFilter with single store overrides selectedBranches', () {
        final result = StoreResolverHelper.resolveTargetStoreIds(['store_001', 'store_002'], storeFilter: 'store_002');
        expect(result, equals(['store_002']));
      });

      test('Staff role (non-admin / non-supervisor) is strictly locked to assigned store', () {
        const staff1 = UserAccount(
          username: 'nhanvien1',
          displayName: 'Nhân Viên 1',
          role: 'nhanvien',
          storeId: 'store_001',
        );

        final result1 = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001', 'store_002'],
          user: staff1,
        );
        expect(result1, equals(['store_001']));

        const staff2 = UserAccount(
          username: 'nhanvien2',
          displayName: 'Nhân Viên 2',
          role: 'nhanvien',
          storeId: 'store_002',
        );

        final result2 = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001'],
          user: staff2,
        );
        expect(result2, equals(['store_002']));
      });

      test('Supervisor and Admin roles have full cross-store access', () {
        const admin = UserAccount(
          username: 'admin',
          displayName: 'Quản Trị Viên',
          role: 'admin',
          storeId: 'store_001',
        );

        final result = StoreResolverHelper.resolveTargetStoreIds(
          ['store_001', 'store_002'],
          user: admin,
        );
        expect(result, containsAll(['store_001', 'store_002']));
        expect(result.length, equals(2));
      });
    });
  });
}
