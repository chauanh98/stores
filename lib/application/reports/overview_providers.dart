import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
        return DateTimeRange(start: today, end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999));
      case OverviewTimeRange.yesterday:
        final yesterday = today.subtract(const Duration(days: 1));
        return DateTimeRange(start: yesterday, end: DateTime(yesterday.year, yesterday.month, yesterday.day, 23, 59, 59, 999));
      case OverviewTimeRange.last7Days:
        return DateTimeRange(start: today.subtract(const Duration(days: 6)), end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999));
      case OverviewTimeRange.thisMonth:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999));
      case OverviewTimeRange.lastMonth:
        final firstOfThisMonth = DateTime(now.year, now.month, 1);
        final lastOfLastMonth = firstOfThisMonth.subtract(const Duration(days: 1));
        final firstOfLastMonth = DateTime(lastOfLastMonth.year, lastOfLastMonth.month, 1);
        return DateTimeRange(
            start: firstOfLastMonth,
            end: DateTime(lastOfLastMonth.year, lastOfLastMonth.month, lastOfLastMonth.day, 23, 59, 59, 999));
      case OverviewTimeRange.custom:
        return DateTimeRange(start: today, end: DateTime(now.year, now.month, now.day, 23, 59, 59, 999));
    }
  }
}

// Provider quản lý khoảng thời gian lọc hiện tại
final selectedTimeRangeTypeProvider = StateProvider<OverviewTimeRange>((ref) => OverviewTimeRange.thisMonth);

// Provider quản lý khoảng thời gian chi tiết (hữu ích cho chế độ custom)
final customDateRangeProvider = StateProvider<DateTimeRange>((ref) {
  return OverviewTimeRange.thisMonth.getRange();
});

// Getter cho khoảng thời gian thực tế đang áp dụng
final activeDateRangeProvider = Provider<DateTimeRange>((ref) {
  final type = ref.watch(selectedTimeRangeTypeProvider);
  if (type == OverviewTimeRange.custom) {
    return ref.watch(customDateRangeProvider);
  }
  return type.getRange();
});

// Định nghĩa Chi nhánh
class Branch {
  final String id;
  final String name;

  const Branch(this.id, this.name);
}

// Danh sách chi nhánh mẫu
const mockBranches = [
  Branch('branch_1', 'Cửa hàng Hà Nội'),
  Branch('branch_2', 'Cửa hàng TP.HCM'),
];

// Lấy danh sách chi nhánh động dựa trên store đang hoạt động
List<Branch> getMockBranches(String currentStoreId) {
  if (currentStoreId == 'store_002') {
    return const [
      Branch('branch_1', 'Cửa hàng TP.HCM'),
      Branch('branch_2', 'Cửa hàng Hà Nội'),
    ];
  }
  return const [
    Branch('branch_1', 'Cửa hàng Hà Nội'),
    Branch('branch_2', 'Cửa hàng TP.HCM'),
  ];
}

// Provider danh sách các chi nhánh được chọn (mặc định chọn tất cả)
class SelectedBranchesNotifier extends StateNotifier<List<String>> {
  SelectedBranchesNotifier() : super(mockBranches.map((b) => b.id).toList());

  void toggleBranch(String branchId) {
    if (state.contains(branchId)) {
      // Đảm bảo phải chọn ít nhất 1 chi nhánh
      if (state.length > 1) {
        state = state.where((id) => id != branchId).toList();
      }
    } else {
      state = [...state, branchId];
    }
  }

  void selectAll() {
    state = mockBranches.map((b) => b.id).toList();
  }

  void clearAll() {
    // Để tránh state trống rỗng lỗi hệ thống, chọn chi nhánh đầu tiên làm fallback
    state = [mockBranches.first.id];
  }
}

final selectedBranchesProvider = StateNotifierProvider<SelectedBranchesNotifier, List<String>>((ref) {
  return SelectedBranchesNotifier();
});

// Provider quản lý bộ lọc cửa hàng được chọn xem báo cáo trên trang Tổng quan (Chỉ dùng cho Admin)
// Mặc định null nghĩa là xem cửa hàng hoạt động hiện tại (currentStoreIdProvider)
// Giá trị 'all' nghĩa là xem gộp Tất cả cửa hàng
final selectedStoreFilterProvider = StateProvider<String?>((ref) => null);
