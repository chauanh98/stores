import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/filter_storage_service.dart';
import '../../domain/entities/user_account.dart';
import '../auth/auth_providers.dart';

// State ẩn/hiện lợi nhuận
final profitVisibilityProvider = StateProvider<bool>((ref) => true);

// Các khoảng thời gian lọc
enum OverviewTimeRange {
  today,
  yesterday,
  last7Days,
  thisMonth,
  lastMonth,
  custom;

  String get label {
    switch (this) {
      case OverviewTimeRange.today:
        return 'Hôm nay';
      case OverviewTimeRange.yesterday:
        return 'Hôm qua';
      case OverviewTimeRange.last7Days:
        return '7 ngày qua';
      case OverviewTimeRange.thisMonth:
        return 'Tháng này';
      case OverviewTimeRange.lastMonth:
        return 'Tháng trước';
      case OverviewTimeRange.custom:
        return 'Tùy chỉnh';
    }
  }

  DateTimeRange getRange() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (this) {
      case OverviewTimeRange.today:
        return DateTimeRange(
            start: today,
            end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999));
      case OverviewTimeRange.yesterday:
        final yesterday = today.subtract(const Duration(days: 1));
        return DateTimeRange(
            start: yesterday,
            end: DateTime(yesterday.year, yesterday.month, yesterday.day, 23,
                59, 59, 999));
      case OverviewTimeRange.last7Days:
        return DateTimeRange(
            start: today.subtract(const Duration(days: 6)),
            end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999));
      case OverviewTimeRange.thisMonth:
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999));
      case OverviewTimeRange.lastMonth:
        final firstOfThisMonth = DateTime(now.year, now.month, 1);
        final lastOfLastMonth =
            firstOfThisMonth.subtract(const Duration(days: 1));
        final firstOfLastMonth =
            DateTime(lastOfLastMonth.year, lastOfLastMonth.month, 1);
        return DateTimeRange(
            start: firstOfLastMonth,
            end: DateTime(lastOfLastMonth.year, lastOfLastMonth.month,
                lastOfLastMonth.day, 23, 59, 59, 999));
      case OverviewTimeRange.custom:
        return DateTimeRange(
            start: today,
            end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999));
    }
  }
}

// --- Overview Date Range Providers ---
final overviewTimeRangeTypeProvider = StateProvider<OverviewTimeRange>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return OverviewTimeRange.today;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('overview', user.username);
  if (saved != null && saved['timeRangeType'] != null) {
    try {
      return OverviewTimeRange.values
          .byName(saved['timeRangeType']?.toString() ?? '');
    } catch (_) {}
  }
  return OverviewTimeRange.today;
});

final overviewCustomDateRangeProvider = StateProvider<DateTimeRange>((ref) {
  final defaultRange = OverviewTimeRange.today.getRange();
  final user = ref.watch(authProvider);
  if (user == null) return defaultRange;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('overview', user.username);
  if (saved != null &&
      saved['customStartDate'] != null &&
      saved['customEndDate'] != null) {
    final start = DateTime.tryParse(saved['customStartDate']?.toString() ?? '');
    final end = DateTime.tryParse(saved['customEndDate']?.toString() ?? '');
    if (start != null && end != null) {
      return DateTimeRange(start: start, end: end);
    }
  }
  return defaultRange;
});

final overviewActiveDateRangeProvider = Provider<DateTimeRange>((ref) {
  final type = ref.watch(overviewTimeRangeTypeProvider);
  if (type == OverviewTimeRange.custom) {
    return ref.watch(overviewCustomDateRangeProvider);
  }
  return type.getRange();
});

// --- Invoices Date Range Providers ---
final invoicesTimeRangeTypeProvider = StateProvider<OverviewTimeRange>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return OverviewTimeRange.thisMonth;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('invoices', user.username);
  if (saved != null && saved['timeRangeType'] != null) {
    try {
      return OverviewTimeRange.values
          .byName(saved['timeRangeType']?.toString() ?? '');
    } catch (_) {}
  }
  return OverviewTimeRange.thisMonth;
});

final invoicesCustomDateRangeProvider = StateProvider<DateTimeRange>((ref) {
  final defaultRange = OverviewTimeRange.thisMonth.getRange();
  final user = ref.watch(authProvider);
  if (user == null) return defaultRange;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('invoices', user.username);
  if (saved != null &&
      saved['customStartDate'] != null &&
      saved['customEndDate'] != null) {
    final start = DateTime.tryParse(saved['customStartDate']?.toString() ?? '');
    final end = DateTime.tryParse(saved['customEndDate']?.toString() ?? '');
    if (start != null && end != null) {
      return DateTimeRange(start: start, end: end);
    }
  }
  return defaultRange;
});

final invoicesActiveDateRangeProvider = Provider<DateTimeRange>((ref) {
  final type = ref.watch(invoicesTimeRangeTypeProvider);
  if (type == OverviewTimeRange.custom) {
    return ref.watch(invoicesCustomDateRangeProvider);
  }
  return type.getRange();
});

// --- Customer Date Range Providers ---
// Null means "All time"
final customerTimeRangeTypeProvider = StateProvider<OverviewTimeRange?>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return null;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('customers', user.username);
  if (saved != null && saved['timeRangeType'] != null) {
    try {
      return OverviewTimeRange.values
          .byName(saved['timeRangeType']?.toString() ?? '');
    } catch (_) {}
  }
  return null;
});

final customerCustomDateRangeProvider = StateProvider<DateTimeRange>((ref) {
  final defaultRange = OverviewTimeRange.thisMonth.getRange();
  final user = ref.watch(authProvider);
  if (user == null) return defaultRange;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('customers', user.username);
  if (saved != null &&
      saved['customStartDate'] != null &&
      saved['customEndDate'] != null) {
    final start = DateTime.tryParse(saved['customStartDate']?.toString() ?? '');
    final end = DateTime.tryParse(saved['customEndDate']?.toString() ?? '');
    if (start != null && end != null) {
      return DateTimeRange(start: start, end: end);
    }
  }
  return defaultRange;
});

final customerActiveDateRangeProvider = Provider<DateTimeRange?>((ref) {
  final type = ref.watch(customerTimeRangeTypeProvider);
  if (type == null) return null;
  if (type == OverviewTimeRange.custom) {
    return ref.watch(customerCustomDateRangeProvider);
  }
  return type.getRange();
});

// Định nghĩa Chi nhánh
class Branch {
  final String id;
  final String name;

  const Branch(this.id, this.name);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Branch &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          name == other.name;

  @override
  int get hashCode => id.hashCode ^ name.hashCode;

  @override
  String toString() => 'Branch(id: $id, name: $name)';
}

// Danh sách chi nhánh mẫu
const mockBranches = [
  Branch('store_001', 'Chi nhánh Đông Thắng'),
  Branch('store_002', 'Chi nhánh Thới Bình'),
];

// Lấy danh sách chi nhánh động dựa trên store đang hoạt động
List<Branch> getMockBranches([String? currentStoreId]) {
  return mockBranches;
}

// Provider quản lý danh sách chi nhánh động lấy từ Firebase
final branchesProvider = Provider<List<Branch>>((ref) {
  final availableStores = ref.watch(availableStoresProvider).valueOrNull ?? {};

  final name1 = availableStores['store_001'] ?? 'Chi nhánh Đông Thắng';
  final name2 = availableStores['store_002'] ?? 'Chi nhánh Thới Bình';

  return [
    Branch('store_001', name1),
    Branch('store_002', name2),
  ];
});

// Provider danh sách các chi nhánh được chọn (mặc định chọn tất cả đối với Admin/Supervisor, khóa theo chi nhánh đối với Nhân viên)
class SelectedBranchesNotifier extends StateNotifier<List<String>> {
  final UserAccount? _user;
  final Ref? _ref;

  SelectedBranchesNotifier([
    this._user,
    List<String>? initialBranches,
    this._ref,
  ]) : super(initialBranches ?? _initialBranches(_user));

  static List<String> _initialBranches(UserAccount? user) {
    if (user != null && user.isStaff) {
      return [user.storeId.isNotEmpty ? user.storeId : 'store_001'];
    }
    return mockBranches.map((b) => b.id).toList();
  }

  void toggleBranch(String branchId) {
    if (_user != null && _user.isStaff) {
      return;
    }
    if (state.contains(branchId)) {
      // Đảm bảo phải chọn ít nhất 1 chi nhánh
      if (state.length > 1) {
        state = state.where((id) => id != branchId).toList();
      }
    } else {
      state = [...state, branchId];
    }
    _persist();
  }

  void selectAll({bool persist = true}) {
    if (_user != null && _user.isStaff) {
      return;
    }
    state = mockBranches.map((b) => b.id).toList();
    if (persist) {
      _persist();
    }
  }

  void clearAll({bool persist = true}) {
    if (_user != null && _user.isStaff) {
      return;
    }
    // Để tránh state trống rỗng lỗi hệ thống, chọn chi nhánh đầu tiên làm fallback
    state = [mockBranches.first.id];
    if (persist) {
      _persist();
    }
  }

  void setBranches(List<String> branches, {bool persist = true}) {
    if (_user != null && _user.isStaff) {
      return;
    }
    if (branches.isEmpty) return;
    state = List<String>.from(branches);
    if (persist) {
      _persist();
    }
  }

  void _persist() {
    final ref = _ref;
    if (ref == null) return;
    try {
      persistOverviewFilters(ref, currentBranches: state);
    } catch (_) {}
  }
}

final selectedBranchesProvider =
    StateNotifierProvider<SelectedBranchesNotifier, List<String>>((ref) {
  final user = ref.watch(authProvider);
  final selectedStore = ref.watch(selectedStoreIdProvider);

  List<String>? initial;
  if (user != null) {
    if (user.isStaff) {
      initial = [user.storeId.isNotEmpty ? user.storeId : 'store_001'];
    } else {
      final storage = ref.watch(filterStorageServiceProvider);
      final saved = storage.loadFilterSync('overview', user.username);
      if (saved != null && saved['selectedBranches'] is List) {
        final list = (saved['selectedBranches'] as List)
            .map((e) => e.toString())
            .where((id) => id.isNotEmpty)
            .toList();
        if (list.isNotEmpty) {
          initial = list;
        }
      }
      if (initial == null &&
          user.isAdmin &&
          selectedStore != null &&
          selectedStore.isNotEmpty &&
          selectedStore != 'all') {
        initial = [selectedStore];
      }
    }
  }

  return SelectedBranchesNotifier(user, initial, ref);
});

// Provider quản lý bộ lọc cửa hàng được chọn xem báo cáo trên trang Tổng quan (Chỉ dùng cho Admin)
// Mặc định null nghĩa là xem cửa hàng hoạt động hiện tại (currentStoreIdProvider)
// Giá trị 'all' nghĩa là xem gộp Tất cả cửa hàng
final selectedStoreFilterProvider = StateProvider<String?>((ref) {
  final user = ref.watch(authProvider);
  if (user == null) return null;

  final storage = ref.watch(filterStorageServiceProvider);
  final saved = storage.loadFilterSync('overview', user.username);
  if (saved != null && saved.containsKey('selectedStoreFilter')) {
    final val = saved['selectedStoreFilter'];
    return val is String ? val : null;
  }
  return null;
});

/// Persists all active Overview filters to user-scoped SharedPreferences:
/// 'filter_prefs_${username}_overview'.
void persistOverviewFilters(
  dynamic ref, {
  List<String>? currentBranches,
  String? currentStoreFilter,
  OverviewTimeRange? timeRangeType,
  DateTimeRange? customDateRange,
}) {
  final user = ref.read(authProvider) as UserAccount?;
  if (user == null) return;
  final storage =
      ref.read(filterStorageServiceProvider) as FilterStorageService;
  final activeTimeRange = timeRangeType ??
      (ref.read(overviewTimeRangeTypeProvider) as OverviewTimeRange);
  final activeCustomRange = customDateRange ??
      (ref.read(overviewCustomDateRangeProvider) as DateTimeRange);
  final branches =
      currentBranches ?? (ref.read(selectedBranchesProvider) as List<String>);
  final storeFilter =
      currentStoreFilter ?? (ref.read(selectedStoreFilterProvider) as String?);

  storage.saveFilter(
      'overview',
      {
        'version': 1,
        'timeRangeType': activeTimeRange.name,
        'customStartDate': activeCustomRange.start.toIso8601String(),
        'customEndDate': activeCustomRange.end.toIso8601String(),
        'selectedBranches': branches,
        'selectedStoreFilter': storeFilter,
      },
      user.username);
}

/// Resets all Overview filters back to defaults and clears storage.
Future<void> resetOverviewFilters(dynamic ref) async {
  final user = ref.read(authProvider) as UserAccount?;
  ref.read(overviewTimeRangeTypeProvider.notifier).state =
      OverviewTimeRange.today;
  ref.read(overviewCustomDateRangeProvider.notifier).state =
      OverviewTimeRange.today.getRange();
  ref.read(selectedBranchesProvider.notifier).selectAll(persist: false);
  ref.read(selectedStoreFilterProvider.notifier).state = null;
  if (user != null) {
    final storage =
        ref.read(filterStorageServiceProvider) as FilterStorageService;
    await storage.clearFilter('overview', user.username);
  }
}
