import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../application/auth/auth_providers.dart';
import '../../../application/reports/overview_providers.dart';
import '../../../core/services/filter_storage_service.dart';

/// Immutable state holding all 5 filter dimensions for InvoicesPage.
class InvoicesFilterState {
  final OverviewTimeRange timeRangeType;
  final DateTimeRange customDateRange;
  final String status;
  final String paymentMethod;
  final String debtStatus;
  final String staff;

  const InvoicesFilterState({
    this.timeRangeType = OverviewTimeRange.thisMonth,
    required this.customDateRange,
    this.status = 'completed',
    this.paymentMethod = 'all',
    this.debtStatus = 'all',
    this.staff = 'all',
  });

  factory InvoicesFilterState.defaults() {
    return InvoicesFilterState(
      timeRangeType: OverviewTimeRange.thisMonth,
      customDateRange: OverviewTimeRange.thisMonth.getRange(),
      status: 'completed',
      paymentMethod: 'all',
      debtStatus: 'all',
      staff: 'all',
    );
  }

  bool get hasActiveFilters => activeFilterCount > 0;

  int get activeFilterCount {
    int count = 0;
    if (timeRangeType != OverviewTimeRange.thisMonth) count++;
    if (status != 'completed') count++;
    if (paymentMethod != 'all') count++;
    if (debtStatus != 'all') count++;
    if (staff != 'all') count++;
    return count;
  }

  InvoicesFilterState copyWith({
    OverviewTimeRange? timeRangeType,
    DateTimeRange? customDateRange,
    String? status,
    String? paymentMethod,
    String? debtStatus,
    String? staff,
  }) {
    return InvoicesFilterState(
      timeRangeType: timeRangeType ?? this.timeRangeType,
      customDateRange: customDateRange ?? this.customDateRange,
      status: status ?? this.status,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      debtStatus: debtStatus ?? this.debtStatus,
      staff: staff ?? this.staff,
    );
  }

  Map<String, dynamic> toJson() => {
        'version': 1,
        'timeRangeType': timeRangeType.name,
        'customStartDate': customDateRange.start.toIso8601String(),
        'customEndDate': customDateRange.end.toIso8601String(),
        'status': status,
        'paymentMethod': paymentMethod,
        'debtStatus': debtStatus,
        'staff': staff,
      };

  factory InvoicesFilterState.fromJson(Map<String, dynamic> json) {
    final defaultRange = OverviewTimeRange.thisMonth.getRange();

    OverviewTimeRange timeRange = OverviewTimeRange.thisMonth;
    if (json['timeRangeType'] != null) {
      try {
        timeRange = OverviewTimeRange.values
            .byName(json['timeRangeType']?.toString() ?? '');
      } catch (_) {
        timeRange = OverviewTimeRange.thisMonth;
      }
    }

    DateTimeRange customRange = defaultRange;
    if (json['customStartDate'] != null && json['customEndDate'] != null) {
      final start =
          DateTime.tryParse(json['customStartDate']?.toString() ?? '');
      final end = DateTime.tryParse(json['customEndDate']?.toString() ?? '');
      if (start != null && end != null) {
        customRange = DateTimeRange(start: start, end: end);
      }
    }

    const validStatuses = {
      'all',
      'completed',
      'returned',
      'draft',
      'cancelled'
    };
    const validPaymentMethods = {'all', 'cash', 'transfer'};
    const validDebtStatuses = {'all', 'paid', 'debt'};

    final rawStatus = json['status']?.toString() ?? 'completed';
    final rawPayment = json['paymentMethod']?.toString() ?? 'all';
    final rawDebt = json['debtStatus']?.toString() ?? 'all';
    final rawStaff = json['staff']?.toString() ?? 'all';

    return InvoicesFilterState(
      timeRangeType: timeRange,
      customDateRange: customRange,
      status: validStatuses.contains(rawStatus) ? rawStatus : 'completed',
      paymentMethod:
          validPaymentMethods.contains(rawPayment) ? rawPayment : 'all',
      debtStatus: validDebtStatuses.contains(rawDebt) ? rawDebt : 'all',
      staff: rawStaff.trim().isEmpty ? 'all' : rawStaff,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoicesFilterState &&
          runtimeType == other.runtimeType &&
          timeRangeType == other.timeRangeType &&
          customDateRange == other.customDateRange &&
          status == other.status &&
          paymentMethod == other.paymentMethod &&
          debtStatus == other.debtStatus &&
          staff == other.staff;

  @override
  int get hashCode => Object.hash(
        timeRangeType,
        customDateRange,
        status,
        paymentMethod,
        debtStatus,
        staff,
      );
}

/// Riverpod Notifier for managing invoice filters with persistence.
class InvoicesFilterNotifier extends Notifier<InvoicesFilterState> {
  static const domainKey = 'invoices';
  bool _isHydrating = false;
  bool _userMutated = false;

  @override
  InvoicesFilterState build() {
    _userMutated = false;
    final user = ref.watch(authProvider);
    final storage = ref.watch(filterStorageServiceProvider);
    final saved =
        user != null ? storage.loadFilterSync(domainKey, user.username) : null;
    final initial = saved != null
        ? InvoicesFilterState.fromJson(saved)
        : InvoicesFilterState.defaults();

    // Trigger async hydration from SharedPreferences if user is authenticated
    if (user != null) {
      _hydrateAsync(user.username);
    }

    // Listen to legacy time range changes for bidirectional sync
    ref.listen<OverviewTimeRange>(invoicesTimeRangeTypeProvider, (prev, next) {
      if (!_isHydrating && state.timeRangeType != next) {
        _userMutated = true;
        state = state.copyWith(timeRangeType: next);
        _persist();
      }
    });

    // Listen to custom date range changes for bidirectional sync
    ref.listen<DateTimeRange>(invoicesCustomDateRangeProvider, (prev, next) {
      if (!_isHydrating && state.customDateRange != next) {
        _userMutated = true;
        state = state.copyWith(
          timeRangeType: OverviewTimeRange.custom,
          customDateRange: next,
        );
        _persist();
      }
    });

    return initial;
  }

  void setHydratedState(InvoicesFilterState hydrated) {
    if (_userMutated) return;
    _isHydrating = true;
    state = hydrated;
    try {
      ref.read(invoicesTimeRangeTypeProvider.notifier).state =
          hydrated.timeRangeType;
      ref.read(invoicesCustomDateRangeProvider.notifier).state =
          hydrated.customDateRange;
    } catch (_) {}
    _isHydrating = false;
  }

  Future<void> _hydrateAsync([String? username]) async {
    try {
      final user = ref.read(authProvider);
      final effectiveUser = username ?? user?.username;
      if (effectiveUser == null) return;
      final storage = ref.read(filterStorageServiceProvider);
      final saved = await storage.loadFilter(domainKey, effectiveUser);
      final currentUser = ref.read(authProvider)?.username;
      if (currentUser != effectiveUser) return;
      if (_userMutated) return;
      if (saved != null) {
        final hydrated = InvoicesFilterState.fromJson(saved);
        setHydratedState(hydrated);
      }
    } catch (_) {
      // Ignored if provider was invalidated or disposed during async disk I/O
    }
  }

  void setStatus(String status) {
    _userMutated = true;
    state = state.copyWith(status: status);
    _persist();
  }

  void setPaymentMethod(String method) {
    _userMutated = true;
    state = state.copyWith(paymentMethod: method);
    _persist();
  }

  void setDebtStatus(String status) {
    _userMutated = true;
    state = state.copyWith(debtStatus: status);
    _persist();
  }

  void setStaff(String staff) {
    _userMutated = true;
    state = state.copyWith(staff: staff);
    _persist();
  }

  void setTimeRangeType(OverviewTimeRange range) {
    _userMutated = true;
    state = state.copyWith(timeRangeType: range);
    ref.read(invoicesTimeRangeTypeProvider.notifier).state = range;
    _persist();
  }

  void setCustomDateRange(DateTimeRange range) {
    _userMutated = true;
    state = state.copyWith(
      timeRangeType: OverviewTimeRange.custom,
      customDateRange: range,
    );
    ref.read(invoicesTimeRangeTypeProvider.notifier).state =
        OverviewTimeRange.custom;
    ref.read(invoicesCustomDateRangeProvider.notifier).state = range;
    _persist();
  }

  Future<void> reset() async {
    _userMutated = true;
    state = InvoicesFilterState.defaults();
    ref.read(invoicesTimeRangeTypeProvider.notifier).state =
        OverviewTimeRange.thisMonth;
    ref.read(invoicesCustomDateRangeProvider.notifier).state =
        OverviewTimeRange.thisMonth.getRange();
    final user = ref.read(authProvider);
    final storage = ref.read(filterStorageServiceProvider);
    await storage.clearFilter(domainKey, user?.username);
  }

  /// Resets in-memory filter state without clearing the user's persisted preferences on disk.
  void resetInMemory() {
    _userMutated = false;
    state = InvoicesFilterState.defaults();
    ref.read(invoicesTimeRangeTypeProvider.notifier).state =
        OverviewTimeRange.thisMonth;
    ref.read(invoicesCustomDateRangeProvider.notifier).state =
        OverviewTimeRange.thisMonth.getRange();
  }

  void _persist() {
    if (_isHydrating) return;
    final user = ref.read(authProvider);
    if (user == null) return;
    final storage = ref.read(filterStorageServiceProvider);
    storage.saveFilter(domainKey, state.toJson(), user.username);
  }
}

/// Provider for [InvoicesFilterState].
final invoicesFilterProvider =
    NotifierProvider<InvoicesFilterNotifier, InvoicesFilterState>(
  InvoicesFilterNotifier.new,
);
