import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';

/// Helper to get Vietnamese weekday name
String formatVietnameseWeekday(DateTime date) {
  switch (date.weekday) {
    case DateTime.monday:
      return 'Thứ Hai';
    case DateTime.tuesday:
      return 'Thứ Ba';
    case DateTime.wednesday:
      return 'Thứ Tư';
    case DateTime.thursday:
      return 'Thứ Năm';
    case DateTime.friday:
      return 'Thứ Sáu';
    case DateTime.saturday:
      return 'Thứ Bảy';
    case DateTime.sunday:
      return 'Chủ Nhật';
    default:
      return '';
  }
}

/// Formats date with relative label in Vietnamese
/// Examples:
/// - "Hôm nay, 21/09/2026"
/// - "Hôm qua, 20/09/2026"
/// - "Thứ Bảy, 19/09/2026"
String formatFriendlyVietnameseDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(date.year, date.month, date.day);
  final dateFormatted = DateFormat('dd/MM/yyyy').format(date);

  final diffDays = today.difference(target).inDays;
  if (diffDays == 0) {
    return 'Hôm nay, $dateFormatted';
  } else if (diffDays == 1) {
    return 'Hôm qua, $dateFormatted';
  } else {
    final weekday = formatVietnameseWeekday(date);
    return '$weekday, $dateFormatted';
  }
}

/// Utility function to group any list of items by date (day level)
/// Returns a Map of normalized midnight DateTime -> List of items for that day.
/// Both dates and items within each date are sorted descending (newest first).
Map<DateTime, List<T>> groupItemsByDate<T>(
  List<T> items,
  DateTime Function(T item) dateSelector, {
  bool descending = true,
  int Function(T a, T b)? itemComparator,
}) {
  final map = <DateTime, List<T>>{};

  for (final item in items) {
    final rawDate = dateSelector(item);
    final dayKey = DateTime(rawDate.year, rawDate.month, rawDate.day);
    map.putIfAbsent(dayKey, () => []).add(item);
  }

  // Sort dates
  final sortedKeys = map.keys.toList()
    ..sort((a, b) => descending ? b.compareTo(a) : a.compareTo(b));

  final sortedMap = <DateTime, List<T>>{};
  for (final key in sortedKeys) {
    final dayItems = map[key]!;
    if (itemComparator != null) {
      dayItems.sort(itemComparator);
    } else {
      dayItems.sort((a, b) {
        final da = dateSelector(a);
        final db = dateSelector(b);
        return descending ? db.compareTo(da) : da.compareTo(db);
      });
    }
    sortedMap[key] = dayItems;
  }

  return sortedMap;
}

/// Reusable Date Group Header Component
class DateGroupHeader extends StatelessWidget {
  final DateTime date;
  final int? itemCount;
  final String itemUnit;
  final double? totalAmount;
  final NumberFormat? currencyFormat;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  const DateGroupHeader({
    super.key,
    required this.date,
    this.itemCount,
    this.itemUnit = 'mục',
    this.totalAmount,
    this.currencyFormat,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final friendlyDate = formatFriendlyVietnameseDate(date);
    final fmt = currencyFormat ?? NumberFormat('#,###', 'vi_VN');

    return Container(
      padding: padding,
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColors.surfaceHighlight.withOpacity(0.45),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.12),
          width: 0.8,
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.calendar_today_outlined,
            size: 13,
            color: AppColors.primary,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 2,
              children: [
                Text(
                  friendlyDate,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
                if (itemCount != null || totalAmount != null)
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (itemCount != null)
                        Text(
                          '($itemCount $itemUnit)',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      if (totalAmount != null) ...[
                        const SizedBox(width: 4),
                        Text(
                          '• ${fmt.format(totalAmount)} đ',
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Generic Date-Grouped ListView
class DateGroupedListView<T> extends StatelessWidget {
  final List<T> items;
  final DateTime Function(T item) dateSelector;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final Widget Function(BuildContext context, DateTime date, List<T> dayItems)?
      headerBuilder;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;
  final Widget? emptyWidget;
  final String itemUnit;
  final double Function(T item)? itemAmountSelector;
  final NumberFormat? currencyFormat;
  final Widget separator;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const DateGroupedListView({
    super.key,
    required this.items,
    required this.dateSelector,
    required this.itemBuilder,
    this.headerBuilder,
    this.controller,
    this.padding = const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    this.emptyWidget,
    this.itemUnit = 'mục',
    this.itemAmountSelector,
    this.currencyFormat,
    this.separator = const SizedBox(height: 8),
    this.shrinkWrap = false,
    this.physics,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return emptyWidget ?? const SizedBox.shrink();
    }

    final grouped = groupItemsByDate(items, dateSelector);
    final dates = grouped.keys.toList();

    // Flatten into list of UI elements (Header or Item)
    final flatList = <_ListItemWrapper<T>>[];
    for (final d in dates) {
      final dayItems = grouped[d]!;
      flatList.add(_ListItemWrapper.header(d, dayItems));
      for (final item in dayItems) {
        flatList.add(_ListItemWrapper.item(item));
      }
    }

    return ListView.builder(
      controller: controller,
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      cacheExtent: 1000,
      itemCount: flatList.length,
      itemBuilder: (context, index) {
        final wrapper = flatList[index];
        if (wrapper.isHeader) {
          if (headerBuilder != null) {
            return headerBuilder!(context, wrapper.date!, wrapper.dayItems!);
          }
          double? totalAmount;
          if (itemAmountSelector != null) {
            totalAmount = wrapper.dayItems!.fold<double>(
              0.0,
              (sum, it) => sum + itemAmountSelector!(it),
            );
          }
          return DateGroupHeader(
            date: wrapper.date!,
            itemCount: wrapper.dayItems!.length,
            itemUnit: itemUnit,
            totalAmount: totalAmount,
            currencyFormat: currencyFormat,
          );
        }

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: itemBuilder(context, wrapper.itemData as T),
        );
      },
    );
  }
}

class _ListItemWrapper<T> {
  final bool isHeader;
  final DateTime? date;
  final List<T>? dayItems;
  final T? itemData;

  const _ListItemWrapper.header(this.date, this.dayItems)
      : isHeader = true,
        itemData = null;

  const _ListItemWrapper.item(this.itemData)
      : isHeader = false,
        date = null,
        dayItems = null;
}
