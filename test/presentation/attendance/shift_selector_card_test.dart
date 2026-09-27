import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/domain/attendance/shift.dart';
import 'package:stores/presentation/attendance/widgets/shift_selector_card.dart';

void main() {
  group('ShiftSelectorCard Widget Tests (R2)', () {
    const morningShift = Shift(
      id: 'shift_morning',
      name: 'Ca Sáng',
      startTime: '08:00',
      endTime: '12:00',
      type: 'morning',
      standardWorkHours: 4.0,
      gracePeriodMinutes: 15,
    );

    const afternoonShift = Shift(
      id: 'shift_afternoon',
      name: 'Ca Chiều',
      startTime: '13:00',
      endTime: '17:30',
      type: 'afternoon',
      standardWorkHours: 4.5,
      gracePeriodMinutes: 15,
    );

    const eveningShift = Shift(
      id: 'shift_evening',
      name: 'Ca Tối',
      startTime: '18:00',
      endTime: '22:00',
      type: 'evening',
      standardWorkHours: 4.0,
      gracePeriodMinutes: 15,
    );

    testWidgets('Renders empty placeholder card when shifts list is empty', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftSelectorCard(
              shifts: const [],
              selectedShift: null,
              onShiftSelected: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Không có ca làm việc nào khả dụng.'), findsOneWidget);
    });

    testWidgets('Renders status badges accurately based on evalTime: open, closed, and upcoming', (tester) async {
      // Evaluation time: 12:30 PM
      // Morning (08:00 - 12:00) -> closed
      // Afternoon (13:00 - 17:30, window opens 12:00) -> open
      // Evening (18:00 - 22:00, window opens 17:00) -> upcoming (opens at 17:00)
      final evalTime = DateTime(2026, 9, 13, 12, 30);

      Shift? clickedShift;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftSelectorCard(
              shifts: const [morningShift, afternoonShift, eveningShift],
              selectedShift: afternoonShift,
              currentTime: evalTime,
              onShiftSelected: (s) => clickedShift = s,
            ),
          ),
        ),
      );

      // Verify title
      expect(find.text('Chọn ca làm việc hôm nay'), findsOneWidget);

      // Verify shift names
      expect(find.text('Ca Sáng'), findsOneWidget);
      expect(find.text('Ca Chiều'), findsOneWidget);
      expect(find.text('Ca Tối'), findsOneWidget);

      // Verify status badges
      // 1. Morning shift is closed: [Đã kết thúc]
      expect(find.text('Đã kết thúc'), findsOneWidget);

      // 2. Afternoon shift is open: [Đang mở ca]
      expect(find.text('Đang mở ca'), findsOneWidget);

      // 3. Evening shift is upcoming: [Chưa mở - Mở lúc 17:00]
      expect(find.text('Chưa mở - Mở lúc 17:00'), findsOneWidget);

      // Verify interaction
      await tester.tap(find.text('Ca Sáng'));
      expect(clickedShift?.id, 'shift_morning');
    });

    testWidgets('Dims non-open shifts with Opacity 0.6 and keeps open shift with Opacity 1.0', (tester) async {
      final evalTime = DateTime(2026, 9, 13, 12, 30);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftSelectorCard(
              shifts: const [morningShift, afternoonShift, eveningShift],
              selectedShift: afternoonShift,
              currentTime: evalTime,
              onShiftSelected: (_) {},
            ),
          ),
        ),
      );

      // Find all Opacity widgets inside the shift items
      final opacities = tester
          .widgetList<Opacity>(find.descendant(
            of: find.byType(ShiftSelectorCard),
            matching: find.byType(Opacity),
          ))
          .toList();

      expect(opacities.length, 3);
      // Morning (closed) -> 0.6
      expect(opacities[0].opacity, 0.6);
      // Afternoon (open) -> 1.0
      expect(opacities[1].opacity, 1.0);
      // Evening (upcoming) -> 0.6
      expect(opacities[2].opacity, 0.6);
    });

    testWidgets('Badges apply proper color styles for open, closed, and upcoming', (tester) async {
      final evalTime = DateTime(2026, 9, 13, 12, 30);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShiftSelectorCard(
              shifts: const [morningShift, afternoonShift, eveningShift],
              selectedShift: afternoonShift,
              currentTime: evalTime,
              onShiftSelected: (_) {},
            ),
          ),
        ),
      );

      // Closed badge styling (red shade)
      final closedText = tester.widget<Text>(find.text('Đã kết thúc'));
      expect(closedText.style?.color, Colors.red.shade700);

      // Open badge styling (green shade)
      final openText = tester.widget<Text>(find.text('Đang mở ca'));
      expect(openText.style?.color, Colors.green.shade700);

      // Upcoming badge styling (orange shade)
      final upcomingText = tester.widget<Text>(find.text('Chưa mở - Mở lúc 17:00'));
      expect(upcomingText.style?.color, Colors.orange.shade800);
    });
  });
}
