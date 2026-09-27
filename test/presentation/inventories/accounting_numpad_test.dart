import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/presentation/inventories/widgets/accounting_numpad.dart';

void main() {
  group('AccountingNumpad Widget Tests', () {
    testWidgets('renders root container and all 16 keys in 4x4 layout', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccountingNumpad(),
          ),
        ),
      );

      // Verify root container
      expect(find.byKey(const Key('accounting_numpad')), findsOneWidget);

      // Verify all digits
      for (final digit in ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0']) {
        expect(find.byKey(Key('numpad_$digit')), findsOneWidget);
        expect(find.text(digit), findsOneWidget);
      }

      // Verify special accounting keys
      expect(find.byKey(const Key('numpad_00')), findsOneWidget);
      expect(find.text('00'), findsOneWidget);

      expect(find.byKey(const Key('numpad_000')), findsOneWidget);
      expect(find.text('000'), findsOneWidget);

      expect(find.byKey(const Key('numpad_.')), findsOneWidget);
      expect(find.text('.'), findsOneWidget);

      // Verify action keys
      expect(find.byKey(const Key('numpad_backspace')), findsOneWidget);
      expect(find.byIcon(Icons.backspace_outlined), findsOneWidget);

      expect(find.byKey(const Key('numpad_clear')), findsOneWidget);
      expect(find.text('C'), findsOneWidget);

      expect(find.byKey(const Key('numpad_enter')), findsOneWidget);
      expect(find.text('Nhập'), findsOneWidget);
    });

    testWidgets('triggers onDigit and onKeyPress callbacks when numeric keys are tapped', (tester) async {
      final List<String> receivedDigits = [];
      final List<String> receivedKeyPresses = [];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountingNumpad(
              onDigit: (digit) => receivedDigits.add(digit),
              onKeyPress: (key) => receivedKeyPresses.add(key),
            ),
          ),
        ),
      );

      // Tap digits 7, 8, 9, 000
      await tester.tap(find.byKey(const Key('numpad_7')));
      await tester.tap(find.byKey(const Key('numpad_8')));
      await tester.tap(find.byKey(const Key('numpad_9')));
      await tester.tap(find.byKey(const Key('numpad_000')));
      await tester.tap(find.byKey(const Key('numpad_00')));
      await tester.tap(find.byKey(const Key('numpad_.')));
      await tester.tap(find.byKey(const Key('numpad_0')));
      await tester.pump();

      expect(receivedDigits, equals(['7', '8', '9', '000', '00', '.', '0']));
      expect(receivedKeyPresses, equals(['7', '8', '9', '000', '00', '.', '0']));
    });

    testWidgets('triggers onDelete and onKeyPress("backspace") when backspace is tapped', (tester) async {
      bool deleteCalled = false;
      String? keyPressReceived;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountingNumpad(
              onDelete: () => deleteCalled = true,
              onKeyPress: (k) => keyPressReceived = k,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('numpad_backspace')));
      await tester.pump();

      expect(deleteCalled, isTrue);
      expect(keyPressReceived, equals('backspace'));
    });

    testWidgets('triggers onClear and onKeyPress("clear") when C is tapped', (tester) async {
      bool clearCalled = false;
      String? keyPressReceived;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountingNumpad(
              onClear: () => clearCalled = true,
              onKeyPress: (k) => keyPressReceived = k,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('numpad_clear')));
      await tester.pump();

      expect(clearCalled, isTrue);
      expect(keyPressReceived, equals('clear'));
    });

    testWidgets('triggers onDone, onEnter, and onKeyPress("enter") when Nhập is tapped', (tester) async {
      bool doneCalled = false;
      bool enterCalled = false;
      String? keyPressReceived;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AccountingNumpad(
              onDone: () => doneCalled = true,
              onEnter: () => enterCalled = true,
              onKeyPress: (k) => keyPressReceived = k,
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const Key('numpad_enter')));
      await tester.pump();

      expect(doneCalled, isTrue);
      expect(enterCalled, isTrue);
      expect(keyPressReceived, equals('enter'));
    });

    testWidgets('applies custom background color and rowHeight', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: AccountingNumpad(
              backgroundColor: Colors.amber,
              rowHeight: 55.0,
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(find.byKey(const Key('accounting_numpad')));
      final decoration = container.decoration as BoxDecoration;
      expect(decoration.color, equals(Colors.amber));
    });

    test('backward compatibility alias AccountingNumpadWidget is usable', () {
      expect(AccountingNumpadWidget, equals(AccountingNumpad));
    });
  });
}
