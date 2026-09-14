import '../../domain/entities/user_account.dart';

/// Helper utility for resolving and normalizing store and branch identifiers
/// across canonical IDs ('store_001', 'store_002'), legacy aliases ('branch_1', 'branch_2'),
/// short codes ('ĐT', 'TB'), and store names ('Chi nhánh Đông Thắng', 'Chi nhánh Thới Bình' / 'Thời Bình').
class StoreResolverHelper {
  /// Normalizes any branch identifier (canonical ID, legacy alias, short code, store name)
  /// to a canonical store ID ('store_001', 'store_002', etc.).
  static String normalizeStoreId(String? input) {
    if (input == null || input.trim().isEmpty) return '';
    final trimmed = input.trim();
    final normalized = trimmed.toLowerCase();

    // Store 001 (Đông Thắng)
    if (normalized == 'store_001' ||
        normalized == 'branch_1' ||
        normalized == 'đt' ||
        normalized == 'dt' ||
        normalized.contains('đông thắng') ||
        normalized.contains('dong thang') ||
        normalized == 'dongthang') {
      return 'store_001';
    }

    // Store 002 (Thới Bình / Thời Bình)
    if (normalized == 'store_002' ||
        normalized == 'branch_2' ||
        normalized == 'tb' ||
        normalized.contains('thới bình') ||
        normalized.contains('thời bình') ||
        normalized.contains('thoi binh') ||
        normalized == 'thoibinh') {
      return 'store_002';
    }

    return trimmed;
  }

  /// Resolves selected branches into a list of canonical store IDs.
  ///
  /// Supports:
  /// - `selectedBranches`: list of branch identifiers
  /// - `availableStoreIds`: optional list of available store IDs (defaults to `['store_001', 'store_002']`)
  /// - `currentStoreId`: current active store ID
  /// - `user`: user account for role/permission check (e.g. staff locked to storeId)
  /// - `storeFilter`: explicit store filter ('all', single store, or null)
  /// - `availableStores`: map of store ID to store name
  static List<String> resolveTargetStoreIds(
    List<String> selectedBranches, {
    List<String>? availableStoreIds,
    String? currentStoreId,
    UserAccount? user,
    String? storeFilter,
    Map<String, String>? availableStores,
  }) {
    // 1. Staff role (non-admin/non-supervisor): strictly limited to assigned storeId
    if (user != null && !user.canSwitchStore) {
      final staffStore = user.storeId.isNotEmpty
          ? user.storeId
          : (currentStoreId != null && currentStoreId.isNotEmpty
              ? currentStoreId
              : 'store_001');
      final norm = normalizeStoreId(staffStore);
      return [norm.isNotEmpty ? norm : staffStore];
    }

    // 2. Explicit 'all' filter
    if (storeFilter == 'all') {
      if (availableStores != null && availableStores.isNotEmpty) {
        final stores = availableStores.keys
            .map(normalizeStoreId)
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (stores.isNotEmpty) return stores;
      }
      if (availableStoreIds != null && availableStoreIds.isNotEmpty) {
        final stores = availableStoreIds
            .map(normalizeStoreId)
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (stores.isNotEmpty) return stores;
      }
      return ['store_001', 'store_002'];
    }

    // 3. Explicit single store filter
    if (storeFilter != null && storeFilter.isNotEmpty && storeFilter != 'all') {
      final norm = normalizeStoreId(storeFilter);
      return [norm.isNotEmpty ? norm : storeFilter];
    }

    // 4. Resolve from selectedBranches
    final Set<String> targetStoreIds = {};
    for (final branch in selectedBranches) {
      final norm = normalizeStoreId(branch);
      if (norm.isNotEmpty) {
        targetStoreIds.add(norm);
      }
    }

    // 5. Fallback if empty
    if (targetStoreIds.isEmpty) {
      if (availableStoreIds != null && availableStoreIds.isNotEmpty) {
        final stores = availableStoreIds
            .map(normalizeStoreId)
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (stores.isNotEmpty) return stores;
      }
      if (availableStores != null && availableStores.isNotEmpty) {
        final stores = availableStores.keys
            .map(normalizeStoreId)
            .where((id) => id.isNotEmpty)
            .toSet()
            .toList();
        if (stores.isNotEmpty) return stores;
      }
      if (currentStoreId != null && currentStoreId.isNotEmpty) {
        final normCurrent = normalizeStoreId(currentStoreId);
        return [normCurrent.isNotEmpty ? normCurrent : currentStoreId];
      }
      return ['store_001', 'store_002'];
    }

    return targetStoreIds.toList();
  }
}
