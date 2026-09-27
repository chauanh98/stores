import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/extensions/context_extensions.dart';

void main() {
  group('BuildContextL10nX & AppLocalizations Parity Verification', () {
    testWidgets('context.l10n resolves Vietnamese keys correctly', (tester) async {
      late String continueText;
      late String draftReceiptText;
      late String inventoryCreateReceiptText;
      late String attendanceShiftConfirmText;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              continueText = context.l10n.commonContinue;
              draftReceiptText = context.l10n.commonDraftReceipt;
              inventoryCreateReceiptText = context.l10n.inventoryCreateReceipt;
              attendanceShiftConfirmText =
                  context.l10n.attendanceDeleteShiftConfirm('Ca Sáng');
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(continueText, 'Tiếp tục');
      expect(draftReceiptText, 'Phiếu tạm');
      expect(inventoryCreateReceiptText, 'Tạo phiếu nhập hàng');
      expect(attendanceShiftConfirmText, 'Bạn có chắc muốn xóa ca "Ca Sáng"?');
    });

    testWidgets('context.l10n resolves English keys correctly with full parity', (tester) async {
      late String continueText;
      late String draftReceiptText;
      late String inventoryCreateReceiptText;
      late String attendanceShiftConfirmText;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              continueText = context.l10n.commonContinue;
              draftReceiptText = context.l10n.commonDraftReceipt;
              inventoryCreateReceiptText = context.l10n.inventoryCreateReceipt;
              attendanceShiftConfirmText =
                  context.l10n.attendanceDeleteShiftConfirm('Morning Shift');
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(continueText, 'Continue');
      expect(draftReceiptText, 'Draft Receipt');
      expect(inventoryCreateReceiptText, 'Create Stock In Receipt');
      expect(attendanceShiftConfirmText,
          'Are you sure you want to delete shift "Morning Shift"?');
    });
  });
}
