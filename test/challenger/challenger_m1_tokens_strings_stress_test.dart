import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/core/constants/app_strings.dart';
import 'package:stores/core/extensions/context_extensions.dart';
import 'package:stores/core/theme/app_colors.dart';

void main() {
  group('Milestone 1 Adversarial Challenge: AppColors Property-Based Checks', () {
    // Comprehensive dictionary of all 155 AppColors tokens
    final Map<String, Color> allColors = {
      'primary': AppColors.primary,
      'primaryLight': AppColors.primaryLight,
      'primaryMedium': AppColors.primaryMedium,
      'primaryDark': AppColors.primaryDark,
      'primaryAction': AppColors.primaryAction,
      'onPrimary': AppColors.onPrimary,
      'secondary': AppColors.secondary,
      'secondaryLight': AppColors.secondaryLight,
      'secondaryDark': AppColors.secondaryDark,
      'onSecondary': AppColors.onSecondary,
      'success': AppColors.success,
      'successLight': AppColors.successLight,
      'successMedium': AppColors.successMedium,
      'successDark': AppColors.successDark,
      'successBorder': AppColors.successBorder,
      'successSubtle': AppColors.successSubtle,
      'onSuccess': AppColors.onSuccess,
      'warning': AppColors.warning,
      'warningLight': AppColors.warningLight,
      'warningMedium': AppColors.warningMedium,
      'warningDark': AppColors.warningDark,
      'warningDeep': AppColors.warningDeep,
      'warningBorder': AppColors.warningBorder,
      'warningSubtle': AppColors.warningSubtle,
      'onWarning': AppColors.onWarning,
      'pending': AppColors.pending,
      'pendingLight': AppColors.pendingLight,
      'draft': AppColors.draft,
      'draftLight': AppColors.draftLight,
      'danger': AppColors.danger,
      'dangerLight': AppColors.dangerLight,
      'dangerMedium': AppColors.dangerMedium,
      'dangerDark': AppColors.dangerDark,
      'dangerDeep': AppColors.dangerDeep,
      'dangerBorder': AppColors.dangerBorder,
      'dangerSubtle': AppColors.dangerSubtle,
      'dangerLightest': AppColors.dangerLightest,
      'onDanger': AppColors.onDanger,
      'cancelled': AppColors.cancelled,
      'cancelledLight': AppColors.cancelledLight,
      'info': AppColors.info,
      'infoLight': AppColors.infoLight,
      'infoDark': AppColors.infoDark,
      'infoBorder': AppColors.infoBorder,
      'infoSubtle': AppColors.infoSubtle,
      'onInfo': AppColors.onInfo,
      'supervisor': AppColors.supervisor,
      'supervisorLight': AppColors.supervisorLight,
      'supervisorDark': AppColors.supervisorDark,
      'white': AppColors.white,
      'white70': AppColors.white70,
      'transparent': AppColors.transparent,
      'black': AppColors.black,
      'overlay': AppColors.overlay,
      'scrim': AppColors.scrim,
      'background': AppColors.background,
      'surface': AppColors.surface,
      'surfaceLight': AppColors.surfaceLight,
      'surfaceCard': AppColors.surfaceCard,
      'cardBackground': AppColors.cardBackground,
      'surfaceContainer': AppColors.surfaceContainer,
      'surfaceHighlight': AppColors.surfaceHighlight,
      'surfaceInfo': AppColors.surfaceInfo,
      'grey50': AppColors.grey50,
      'grey100': AppColors.grey100,
      'grey200': AppColors.grey200,
      'grey300': AppColors.grey300,
      'grey400': AppColors.grey400,
      'grey500': AppColors.grey500,
      'grey600': AppColors.grey600,
      'grey700': AppColors.grey700,
      'grey800': AppColors.grey800,
      'grey900': AppColors.grey900,
      'border': AppColors.border,
      'borderLight': AppColors.borderLight,
      'borderSubtle': AppColors.borderSubtle,
      'divider': AppColors.divider,
      'dividerLight': AppColors.dividerLight,
      'dividerSubtle': AppColors.dividerSubtle,
      'textPrimary': AppColors.textPrimary,
      'textSecondary': AppColors.textSecondary,
      'textTertiary': AppColors.textTertiary,
      'textHeadline': AppColors.textHeadline,
      'textTitle': AppColors.textTitle,
      'textBodyDark': AppColors.textBodyDark,
      'textSlate600': AppColors.textSlate600,
      'textMuted': AppColors.textMuted,
      'textDisabled': AppColors.textDisabled,
      'branchDongThangText': AppColors.branchDongThangText,
      'branchDongThangBg': AppColors.branchDongThangBg,
      'branchDongThangBorder': AppColors.branchDongThangBorder,
      'branchThoiBinhText': AppColors.branchThoiBinhText,
      'branchThoiBinhBg': AppColors.branchThoiBinhBg,
      'branchThoiBinhBorder': AppColors.branchThoiBinhBorder,
      'receiptCompletedText': AppColors.receiptCompletedText,
      'receiptCompletedBg': AppColors.receiptCompletedBg,
      'receiptCompletedBorder': AppColors.receiptCompletedBorder,
      'receiptDraftText': AppColors.receiptDraftText,
      'receiptDraftBg': AppColors.receiptDraftBg,
      'receiptDraftBorder': AppColors.receiptDraftBorder,
      'receiptCancelledText': AppColors.receiptCancelledText,
      'receiptCancelledBg': AppColors.receiptCancelledBg,
      'receiptCancelledBorder': AppColors.receiptCancelledBorder,
      'debtOwingText': AppColors.debtOwingText,
      'debtOwingBg': AppColors.debtOwingBg,
      'debtSettledText': AppColors.debtSettledText,
      'debtSettledBg': AppColors.debtSettledBg,
      'debtSurplusText': AppColors.debtSurplusText,
      'debtSurplusBg': AppColors.debtSurplusBg,
      'attendanceOnTimeText': AppColors.attendanceOnTimeText,
      'attendanceOnTimeBg': AppColors.attendanceOnTimeBg,
      'attendanceLateText': AppColors.attendanceLateText,
      'attendanceLateBg': AppColors.attendanceLateBg,
      'attendanceEarlyLeaveText': AppColors.attendanceEarlyLeaveText,
      'attendanceEarlyLeaveBg': AppColors.attendanceEarlyLeaveBg,
      'chartBlue': AppColors.chartBlue,
      'chartLightBlue': AppColors.chartLightBlue,
      'chartGreen': AppColors.chartGreen,
      'chartOrange': AppColors.chartOrange,
      'chartPurple': AppColors.chartPurple,
      'chartRed': AppColors.chartRed,
      'chartTeal': AppColors.chartTeal,
      'chartYellow': AppColors.chartYellow,
      'chartIndigo': AppColors.chartIndigo,
      'medalGold': AppColors.medalGold,
      'medalSilver': AppColors.medalSilver,
      'medalBronze': AppColors.medalBronze,
      'softBlueBorder': AppColors.softBlueBorder,
      'softBlueSurface': AppColors.softBlueSurface,
      'orangeLight': AppColors.orangeLight,
      'orangeDark': AppColors.orangeDark,
      'purpleLight': AppColors.purpleLight,
      'purpleDark': AppColors.purpleDark,
      'tealLight': AppColors.tealLight,
      'skyBorder': AppColors.skyBorder,
      'orange100': AppColors.orange100,
      'orange700': AppColors.orange700,
      'thumbnailDefaultBg': AppColors.thumbnailDefaultBg,
      'thumbnailDefaultFg': AppColors.thumbnailDefaultFg,
      'thumbnailBlueBg': AppColors.thumbnailBlueBg,
      'thumbnailBlueFg': AppColors.thumbnailBlueFg,
      'thumbnailPurpleBg': AppColors.thumbnailPurpleBg,
      'thumbnailPurpleFg': AppColors.thumbnailPurpleFg,
      'thumbnailTealBg': AppColors.thumbnailTealBg,
      'thumbnailTealFg': AppColors.thumbnailTealFg,
      'thumbnailAmberBg': AppColors.thumbnailAmberBg,
      'thumbnailAmberFg': AppColors.thumbnailAmberFg,
      'thumbnailRedBg': AppColors.thumbnailRedBg,
      'thumbnailRedFg': AppColors.thumbnailRedFg,
      'thumbnailGreenBg': AppColors.thumbnailGreenBg,
      'thumbnailGreenFg': AppColors.thumbnailGreenFg,
      'thumbnailRoseBg': AppColors.thumbnailRoseBg,
      'thumbnailRoseFg': AppColors.thumbnailRoseFg,
      'thumbnailSlateBg': AppColors.thumbnailSlateBg,
      'thumbnailSlateFg': AppColors.thumbnailSlateFg,
    };

    test('Property 1: All 155 color constants are non-null and within valid 32-bit ARGB range', () {
      expect(allColors.length, 155, reason: 'Must contain exactly 155 color tokens');
      for (final entry in allColors.entries) {
        final name = entry.key;
        final color = entry.value;

        expect(color, isNotNull, reason: 'Color $name must not be null');
        expect(color.value >= 0x00000000 && color.value <= 0xFFFFFFFF, isTrue,
            reason: 'Color $name value (${color.value.toRadixString(16)}) must be in 32-bit ARGB range');

        // Channel boundaries
        expect(color.alpha >= 0 && color.alpha <= 255, isTrue);
        expect(color.red >= 0 && color.red <= 255, isTrue);
        expect(color.green >= 0 && color.green <= 255, isTrue);
        expect(color.blue >= 0 && color.blue <= 255, isTrue);
      }
    });

    test('Property 2: Alpha channel integrity (transparent vs translucent vs opaque)', () {
      final transparentTokens = {'transparent'};
      final translucentTokens = {'white70', 'overlay', 'scrim'};

      // Explicit alpha values
      expect(AppColors.transparent.alpha, 0, reason: 'AppColors.transparent must have alpha 0');
      expect(AppColors.white70.alpha, 0xB3, reason: 'AppColors.white70 must have alpha 0xB3 (179)');
      expect(AppColors.overlay.alpha, 0x80, reason: 'AppColors.overlay must have alpha 0x80 (128)');
      expect(AppColors.scrim.alpha, 0x52, reason: 'AppColors.scrim must have alpha 0x52 (82)');

      // All remaining 151 tokens must be 100% opaque
      for (final entry in allColors.entries) {
        if (!transparentTokens.contains(entry.key) && !translucentTokens.contains(entry.key)) {
          expect(entry.value.alpha, 255,
              reason: 'Opaque token ${entry.key} must have alpha = 255, found ${entry.value.alpha}');
        }
      }
    });

    test('Property 3: Semantic status alias consistency', () {
      // Pending == Warning
      expect(AppColors.pending, equals(AppColors.warning));
      expect(AppColors.pendingLight, equals(AppColors.warningLight));

      // Draft == Warning
      expect(AppColors.draft, equals(AppColors.warning));
      expect(AppColors.draftLight, equals(AppColors.warningLight));

      // Cancelled == Danger
      expect(AppColors.cancelled, equals(AppColors.danger));
      expect(AppColors.cancelledLight, equals(AppColors.dangerLight));
    });

    test('Property 4: Semantic distinctiveness (states do not accidentally collide)', () {
      expect(AppColors.success != AppColors.warning, isTrue);
      expect(AppColors.warning != AppColors.danger, isTrue);
      expect(AppColors.danger != AppColors.info, isTrue);
      expect(AppColors.info != AppColors.primary, isTrue);

      // Branch color distinctiveness (Đông Thắng Blue vs Thới Bình Green)
      expect(AppColors.branchDongThangText != AppColors.branchThoiBinhText, isTrue);
      expect(AppColors.branchDongThangBg != AppColors.branchThoiBinhBg, isTrue);
      expect(AppColors.branchDongThangBorder != AppColors.branchThoiBinhBorder, isTrue);
    });

    // Helper function for WCAG relative luminance & contrast ratio
    double getLuminance(Color color) {
      double transform(double c) {
        c = c / 255.0;
        return c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055) * ((c + 0.055) / 1.055);
      }

      final r = transform(color.red.toDouble());
      final g = transform(color.green.toDouble());
      final b = transform(color.blue.toDouble());
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    double getContrastRatio(Color foreground, Color background) {
      final l1 = getLuminance(foreground);
      final l2 = getLuminance(background);
      final lighter = l1 > l2 ? l1 : l2;
      final darker = l1 > l2 ? l2 : l1;
      return (lighter + 0.05) / (darker + 0.05);
    }

    test('Property 5: Accessibility & WCAG contrast ratios on key badges and text', () {
      // Primary text on primary button: white on primary blue
      final onPrimaryContrast = getContrastRatio(AppColors.onPrimary, AppColors.primary);
      expect(onPrimaryContrast >= 4.5, isTrue,
          reason: 'onPrimary on primary contrast ratio should be >= 4.5 (was $onPrimaryContrast)');

      // Branch badges: UI components / badge text contrast ratio >= 3.0 (WCAG 2.1 AA for graphical/UI components)
      final dtContrast = getContrastRatio(AppColors.branchDongThangText, AppColors.branchDongThangBg);
      expect(dtContrast >= 3.0, isTrue,
          reason: 'branchDongThangText on branchDongThangBg contrast should be >= 3.0 (was $dtContrast)');

      final tbContrast = getContrastRatio(AppColors.branchThoiBinhText, AppColors.branchThoiBinhBg);
      expect(tbContrast >= 3.0, isTrue,
          reason: 'branchThoiBinhText on branchThoiBinhBg contrast should be >= 3.0 (was $tbContrast)');

      // Receipt Badges: text on background contrast ratio >= 3.0
      final completedContrast = getContrastRatio(AppColors.receiptCompletedText, AppColors.receiptCompletedBg);
      expect(completedContrast >= 3.0, isTrue,
          reason: 'receiptCompletedText on receiptCompletedBg contrast should be >= 3.0 (was $completedContrast)');

      final draftContrast = getContrastRatio(AppColors.receiptDraftText, AppColors.receiptDraftBg);
      expect(draftContrast >= 3.0, isTrue,
          reason: 'receiptDraftText on receiptDraftBg contrast should be >= 3.0 (was $draftContrast)');

      final cancelledContrast = getContrastRatio(AppColors.receiptCancelledText, AppColors.receiptCancelledBg);
      expect(cancelledContrast >= 3.0, isTrue,
          reason: 'receiptCancelledText on receiptCancelledBg contrast should be >= 3.0 (was $cancelledContrast)');

      // Debt Badges
      final debtOwingContrast = getContrastRatio(AppColors.debtOwingText, AppColors.debtOwingBg);
      expect(debtOwingContrast >= 3.0, isTrue,
          reason: 'debtOwingText on debtOwingBg contrast should be >= 3.0 (was $debtOwingContrast)');

      final debtSettledContrast = getContrastRatio(AppColors.debtSettledText, AppColors.debtSettledBg);
      expect(debtSettledContrast >= 3.0, isTrue,
          reason: 'debtSettledText on debtSettledBg contrast should be >= 3.0 (was $debtSettledContrast)');
    });
  });

  group('Milestone 1 Adversarial Challenge: AppStrings Constants Validation', () {
    final Map<String, String> allStrings = {
      'appName': AppStrings.appName,
      'companyName': AppStrings.companyName,
      'currencySymbol': AppStrings.currencySymbol,
      'currencyCode': AppStrings.currencyCode,
      'defaultUnit': AppStrings.defaultUnit,
      'unitPiece': AppStrings.unitPiece,
      'unitSet': AppStrings.unitSet,
      'unitBox': AppStrings.unitBox,
      'unitKg': AppStrings.unitKg,
      'unitMeter': AppStrings.unitMeter,
      'storeDongThangId': AppStrings.storeDongThangId,
      'storeDongThangName': AppStrings.storeDongThangName,
      'storeDongThangShort': AppStrings.storeDongThangShort,
      'storeThoiBinhId': AppStrings.storeThoiBinhId,
      'storeThoiBinhName': AppStrings.storeThoiBinhName,
      'storeThoiBinhShort': AppStrings.storeThoiBinhShort,
      'allStoresId': AppStrings.allStoresId,
      'allStoresName': AppStrings.allStoresName,
      'allStoresCombined': AppStrings.allStoresCombined,
      'paymentMethodCash': AppStrings.paymentMethodCash,
      'paymentMethodTransfer': AppStrings.paymentMethodTransfer,
      'paymentMethodCard': AppStrings.paymentMethodCard,
      'paymentMethodDebt': AppStrings.paymentMethodDebt,
      'paymentLabelCash': AppStrings.paymentLabelCash,
      'paymentLabelTransfer': AppStrings.paymentLabelTransfer,
      'paymentLabelCard': AppStrings.paymentLabelCard,
      'paymentLabelDebt': AppStrings.paymentLabelDebt,
      'statusDraft': AppStrings.statusDraft,
      'statusCompleted': AppStrings.statusCompleted,
      'statusCancelled': AppStrings.statusCancelled,
      'statusPending': AppStrings.statusPending,
      'statusProcessing': AppStrings.statusProcessing,
      'statusDraftLabel': AppStrings.statusDraftLabel,
      'statusCompletedLabel': AppStrings.statusCompletedLabel,
      'statusCancelledLabel': AppStrings.statusCancelledLabel,
      'transactionTypeImport': AppStrings.transactionTypeImport,
      'transactionTypeExport': AppStrings.transactionTypeExport,
      'transactionTypeTransfer': AppStrings.transactionTypeTransfer,
      'transactionTypeAdjustment': AppStrings.transactionTypeAdjustment,
      'transactionTypeReturn': AppStrings.transactionTypeReturn,
      'errorGeneric': AppStrings.errorGeneric,
      'errorNetwork': AppStrings.errorNetwork,
      'errorDatabase': AppStrings.errorDatabase,
      'errorUnauthorized': AppStrings.errorUnauthorized,
      'errorInsufficientStock': AppStrings.errorInsufficientStock,
      'errorInvalidQuantity': AppStrings.errorInvalidQuantity,
      'errorInvalidBranch': AppStrings.errorInvalidBranch,
      'errorSameBranchTransfer': AppStrings.errorSameBranchTransfer,
      'errorOrderAlreadyCancelled': AppStrings.errorOrderAlreadyCancelled,
      'errorCancelReasonRequired': AppStrings.errorCancelReasonRequired,
      'errorCannotDeleteCompletedReceipt': AppStrings.errorCannotDeleteCompletedReceipt,
      'errorDebtExceeded': AppStrings.errorDebtExceeded,
      'errorProductNotFound': AppStrings.errorProductNotFound,
      'errorSupplierNotFound': AppStrings.errorSupplierNotFound,
      'errorCustomerNotFound': AppStrings.errorCustomerNotFound,
      'errorInvalidBarcode': AppStrings.errorInvalidBarcode,
      'noteSupplierPayment': AppStrings.noteSupplierPayment,
      'noteSupplierAdjustment': AppStrings.noteSupplierAdjustment,
      'noteStockInDebt': AppStrings.noteStockInDebt,
      'noteCustomerDebtAdjustment': AppStrings.noteCustomerDebtAdjustment,
      'noteReturnOrder': AppStrings.noteReturnOrder,
      'noteCancelStockIn': AppStrings.noteCancelStockIn,
      'noteTransferSource': AppStrings.noteTransferSource,
      'noteTransferDestination': AppStrings.noteTransferDestination,
      'dateFormatPattern': AppStrings.dateFormatPattern,
      'dateTimeFormatPattern': AppStrings.dateTimeFormatPattern,
      'timeFormatPattern': AppStrings.timeFormatPattern,
      'monthYearFormatPattern': AppStrings.monthYearFormatPattern,
      'filterToday': AppStrings.filterToday,
      'filterYesterday': AppStrings.filterYesterday,
      'filterLast7Days': AppStrings.filterLast7Days,
      'filterThisMonth': AppStrings.filterThisMonth,
      'filterLastMonth': AppStrings.filterLastMonth,
      'filterCustom': AppStrings.filterCustom,
    };

    test('Property 1: All 74 string constants are non-empty and have no accidental whitespace padding', () {
      expect(allStrings.length, 74, reason: 'Must contain exactly 74 string constants');
      for (final entry in allStrings.entries) {
        final key = entry.key;
        final value = entry.value;

        expect(value.trim(), isNotEmpty, reason: '$key must not be empty or whitespace-only');
        expect(value.trim(), equals(value), reason: '$key must not have leading or trailing whitespace');
      }
    });

    test('Property 2: Store branch identifiers and system names match authoritative specs', () {
      expect(AppStrings.storeDongThangId, 'store_001');
      expect(AppStrings.storeThoiBinhId, 'store_002');
      expect(AppStrings.allStoresId, 'all');

      expect(AppStrings.storeDongThangName, 'Chi nhánh Đông Thắng');
      expect(AppStrings.storeThoiBinhName, 'Chi nhánh Thới Bình');
      expect(AppStrings.allStoresName, 'Tất cả chi nhánh');
      expect(AppStrings.allStoresCombined, contains('Toàn hệ thống'));
    });

    test('Property 3: Payment method keys match persistence schema', () {
      expect(AppStrings.paymentMethodCash, 'cash');
      expect(AppStrings.paymentMethodTransfer, 'transfer');
      expect(AppStrings.paymentMethodCard, 'card');
      expect(AppStrings.paymentMethodDebt, 'debt');

      // Unique keys
      final methods = {
        AppStrings.paymentMethodCash,
        AppStrings.paymentMethodTransfer,
        AppStrings.paymentMethodCard,
        AppStrings.paymentMethodDebt,
      };
      expect(methods.length, 4, reason: 'Payment methods must be distinct');
    });

    test('Property 4: Transaction status codes and Vietnamese labels', () {
      expect(AppStrings.statusDraft, 'draft');
      expect(AppStrings.statusCompleted, 'completed');
      expect(AppStrings.statusCancelled, 'cancelled');
      expect(AppStrings.statusPending, 'pending');
      expect(AppStrings.statusProcessing, 'processing');

      expect(AppStrings.statusDraftLabel, 'Phiếu tạm');
      expect(AppStrings.statusCompletedLabel, 'Đã hoàn thành');
      expect(AppStrings.statusCancelledLabel, 'Đã hủy');
    });

    test('Property 5: Inventory transaction types match Clean Architecture domain', () {
      final types = [
        AppStrings.transactionTypeImport,
        AppStrings.transactionTypeExport,
        AppStrings.transactionTypeTransfer,
        AppStrings.transactionTypeAdjustment,
        AppStrings.transactionTypeReturn,
      ];
      expect(types.toSet().length, 5, reason: 'All 5 transaction types must be distinct');
      expect(types, ['import', 'export', 'transfer', 'adjustment', 'return']);
    });

    test('Property 6: Date formatting patterns parse and format with intl without throwing', () {
      final testDate = DateTime(2026, 9, 27, 14, 30, 45);

      final dateFormatted = DateFormat(AppStrings.dateFormatPattern).format(testDate);
      expect(dateFormatted, '27/09/2026');

      final dateTimeFormatted = DateFormat(AppStrings.dateTimeFormatPattern).format(testDate);
      expect(dateTimeFormatted, '27/09/2026 14:30');

      final timeFormatted = DateFormat(AppStrings.timeFormatPattern).format(testDate);
      expect(timeFormatted, '14:30');

      final monthYearFormatted = DateFormat(AppStrings.monthYearFormatPattern).format(testDate);
      expect(monthYearFormatted, '09/2026');

      // Round-trip parsing
      final parsedDate = DateFormat(AppStrings.dateFormatPattern).parse('27/09/2026');
      expect(parsedDate.day, 27);
      expect(parsedDate.month, 9);
      expect(parsedDate.year, 2026);
    });

    test('Property 7: Critical business error messages contain necessary domain directives', () {
      expect(AppStrings.errorCannotDeleteCompletedReceipt, contains('Không thể xóa phiếu nhập đã hoàn thành'));
      expect(AppStrings.errorCannotDeleteCompletedReceipt, contains('hoàn trả tồn kho và công nợ'));
      expect(AppStrings.errorCancelReasonRequired, contains('Lý do hủy'));
      expect(AppStrings.errorOrderAlreadyCancelled, contains('đã được hủy trước đó'));
      expect(AppStrings.errorSameBranchTransfer, contains('cùng một kho'));
    });
  });

  group('Milestone 1 Adversarial Challenge: L10n & BuildContext Extension Verification', () {
    testWidgets('Extension context.l10n delivers complete localization for newly added keys in Vietnamese',
        (tester) async {
      late String saveDraft;
      late String draftReceipt;
      late String completed;
      late String cancelled;
      late String createReceipt;
      late String receiptDetail;
      late String deleteShiftConfirm;
      late String accountDeleteConfirm;
      late String confirmExitTitle;

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
              final l10n = context.l10n;
              saveDraft = l10n.commonSaveDraft;
              draftReceipt = l10n.commonDraftReceipt;
              completed = l10n.commonCompleted;
              cancelled = l10n.commonCancelled;
              createReceipt = l10n.inventoryCreateReceipt;
              receiptDetail = l10n.inventoryReceiptDetail;
              deleteShiftConfirm = l10n.attendanceDeleteShiftConfirm('Ca Tối');
              accountDeleteConfirm = l10n.accountDeleteConfirm('Châu Anh');
              confirmExitTitle = l10n.inventoryConfirmExitTitle;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(saveDraft, 'Lưu tạm');
      expect(draftReceipt, 'Phiếu tạm');
      expect(completed, 'Đã hoàn thành');
      expect(cancelled, 'Đã hủy');
      expect(createReceipt, 'Tạo phiếu nhập hàng');
      expect(receiptDetail, 'Chi tiết phiếu nhập');
      expect(deleteShiftConfirm, 'Bạn có chắc muốn xóa ca "Ca Tối"?');
      expect(accountDeleteConfirm, 'Bạn có chắc chắn muốn xóa tài khoản "Châu Anh" khỏi hệ thống? Hành động này không thể hoàn tác.');
      expect(confirmExitTitle, 'Rời khỏi màn hình nhập hàng?');
    });

    testWidgets('Extension context.l10n delivers complete localization for newly added keys in English',
        (tester) async {
      late String saveDraft;
      late String draftReceipt;
      late String completed;
      late String cancelled;
      late String createReceipt;
      late String receiptDetail;
      late String deleteShiftConfirm;
      late String accountDeleteConfirm;
      late String confirmExitTitle;

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
              final l10n = context.l10n;
              saveDraft = l10n.commonSaveDraft;
              draftReceipt = l10n.commonDraftReceipt;
              completed = l10n.commonCompleted;
              cancelled = l10n.commonCancelled;
              createReceipt = l10n.inventoryCreateReceipt;
              receiptDetail = l10n.inventoryReceiptDetail;
              deleteShiftConfirm = l10n.attendanceDeleteShiftConfirm('Night Shift');
              accountDeleteConfirm = l10n.accountDeleteConfirm('Chau Anh');
              confirmExitTitle = l10n.inventoryConfirmExitTitle;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(saveDraft, 'Save Draft');
      expect(draftReceipt, 'Draft Receipt');
      expect(completed, 'Completed');
      expect(cancelled, 'Cancelled');
      expect(createReceipt, 'Create Stock In Receipt');
      expect(receiptDetail, 'Stock In Receipt Detail');
      expect(deleteShiftConfirm, 'Are you sure you want to delete shift "Night Shift"?');
      expect(accountDeleteConfirm, 'Are you sure you want to delete account "Chau Anh"? This action cannot be undone.');
      expect(confirmExitTitle, 'Leave Stock In Screen?');
    });
  });
}
