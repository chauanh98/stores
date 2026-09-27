import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/presentation/common/widgets/date_grouped_list_view.dart';

class _TestItem {
  final String id;
  final DateTime date;
  final double amount;

  _TestItem({required this.id, required this.date, required this.amount});
}

void main() {
  group('Date Grouping Helper Functions', () {
    test('formatVietnameseWeekday returns correct Vietnamese names', () {
      expect(formatVietnameseWeekday(DateTime(2026, 9, 21)), equals('Thứ Hai'));
      expect(formatVietnameseWeekday(DateTime(2026, 9, 22)), equals('Thứ Ba'));
      expect(formatVietnameseWeekday(DateTime(2026, 9, 23)), equals('Thứ Tư'));
      expect(formatVietnameseWeekday(DateTime(2026, 9, 24)), equals('Thứ Năm'));
      expect(formatVietnameseWeekday(DateTime(2026, 9, 25)), equals('Thứ Sáu'));
      expect(formatVietnameseWeekday(DateTime(2026, 9, 26)), equals('Thứ Bảy'));
      expect(formatVietnameseWeekday(DateTime(2026, 9, 27)), equals('Chủ Nhật'));
    });

    test('groupItemsByDate correctly groups and sorts dates and items descending', () {
      final items = [
        _TestItem(id: '1', date: DateTime(2026, 9, 19, 10, 0), amount: 100),
        _TestItem(id: '2', date: DateTime(2026, 9, 20, 15, 30), amount: 200),
        _TestItem(id: '3', date: DateTime(2026, 9, 19, 16, 17), amount: 300),
        _TestItem(id: '4', date: DateTime(2026, 9, 21, 8, 45), amount: 400),
        _TestItem(id: '5', date: DateTime(2026, 9, 20, 9, 0), amount: 500),
      ];

      final grouped = groupItemsByDate(items, (item) => item.date);

      // Keys should be sorted newest first: 21/09, 20/09, 19/09
      final keys = grouped.keys.toList();
      expect(keys.length, equals(3));
      expect(keys[0], equals(DateTime(2026, 9, 21)));
      expect(keys[1], equals(DateTime(2026, 9, 20)));
      expect(keys[2], equals(DateTime(2026, 9, 19)));

      // 21/09 should have item 4
      expect(grouped[keys[0]]!.map((e) => e.id).toList(), equals(['4']));

      // 20/09 should have item 2 (15:30) then item 5 (09:00)
      expect(grouped[keys[1]]!.map((e) => e.id).toList(), equals(['2', '5']));

      // 19/09 should have item 3 (16:17) then item 1 (10:00)
      expect(grouped[keys[2]]!.map((e) => e.id).toList(), equals(['3', '1']));
    });
  });

  group('DateGroupHeader Widget', () {
    testWidgets('Renders friendly date, item count badge, and total amount', (tester) async {
      final date = DateTime(2026, 9, 19);
      final currencyFormat = NumberFormat('#,###', 'vi_VN');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateGroupHeader(
              date: date,
              itemCount: 3,
              itemUnit: 'hóa đơn',
              totalAmount: 1860000.0,
              currencyFormat: currencyFormat,
            ),
          ),
        ),
      );

      expect(find.textContaining('19/09/2026'), findsOneWidget);
      expect(find.textContaining('3 hóa đơn'), findsOneWidget);
      expect(find.textContaining('1.860.000 đ'), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today_outlined), findsOneWidget);
    });
  });

  group('DateGroupedListView Widget', () {
    testWidgets('Renders headers and item cards in date sections', (tester) async {
      final items = [
        _TestItem(id: 'HD01', date: DateTime(2026, 9, 20, 10, 0), amount: 500000),
        _TestItem(id: 'HD02', date: DateTime(2026, 9, 19, 16, 0), amount: 800000),
        _TestItem(id: 'HD03', date: DateTime(2026, 9, 19, 11, 0), amount: 200000),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DateGroupedListView<_TestItem>(
              items: items,
              dateSelector: (it) => it.date,
              itemUnit: 'đơn',
              itemAmountSelector: (it) => it.amount,
              itemBuilder: (context, it) {
                return Text('ITEM_${it.id}');
              },
            ),
          ),
        ),
      );

      // Should have 2 headers (20/09 and 19/09)
      expect(find.byType(DateGroupHeader), findsNWidgets(2));
      expect(find.text('ITEM_HD01'), findsOneWidget);
      expect(find.text('ITEM_HD02'), findsOneWidget);
      expect(find.text('ITEM_HD03'), findsOneWidget);
    });
  });
}
