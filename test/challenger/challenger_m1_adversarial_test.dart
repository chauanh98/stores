import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/extensions/context_extensions.dart';
import 'package:stores/core/theme/app_colors.dart';

void main() {
  group('Empirical Challenger M1: AppColors Opacity & Alpha Invariants', () {
    test('Verify exact translucency for designated alpha-channel tokens', () {
      expect(AppColors.transparent.alpha, equals(0));
      expect(AppColors.transparent.opacity, equals(0.0));

      expect(AppColors.white70.alpha, equals(0xB3)); // 179
      expect((AppColors.white70.opacity - 0.702).abs() < 0.01, isTrue);

      expect(AppColors.overlay.alpha, equals(0x80)); // 128
      expect((AppColors.overlay.opacity - 0.502).abs() < 0.01, isTrue);

      expect(AppColors.scrim.alpha, equals(0x52)); // 82
      expect((AppColors.scrim.opacity - 0.322).abs() < 0.01, isTrue);
    });

    test('Verify all core brand, status, grayscale and badge tokens are 100% opaque', () {
      final opaqueTokens = <String, Color>{
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
        'danger': AppColors.danger,
        'dangerLight': AppColors.dangerLight,
        'dangerMedium': AppColors.dangerMedium,
        'dangerDark': AppColors.dangerDark,
        'dangerDeep': AppColors.dangerDeep,
        'dangerBorder': AppColors.dangerBorder,
        'dangerSubtle': AppColors.dangerSubtle,
        'onDanger': AppColors.onDanger,
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
        'black': AppColors.black,
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
        'chartGreen': AppColors.chartGreen,
        'chartOrange': AppColors.chartOrange,
        'chartPurple': AppColors.chartPurple,
        'chartRed': AppColors.chartRed,
        'chartTeal': AppColors.chartTeal,
        'chartYellow': AppColors.chartYellow,
        'chartIndigo': AppColors.chartIndigo,
      };

      for (final entry in opaqueTokens.entries) {
        expect(entry.value.alpha, equals(255),
            reason: '${entry.key} must have alpha 255 (0xFF)');
        expect(entry.value.opacity, equals(1.0),
            reason: '${entry.key} must have opacity 1.0');
      }
    });
  });

  group('Empirical Challenger M1: WCAG 2.1 Contrast Stress Testing', () {
    double relativeLuminance(Color c) {
      double channel(int value) {
        final val = value / 255.0;
        return val <= 0.04045
            ? val / 12.92
            : pow((val + 0.055) / 1.055, 2.4).toDouble();
      }

      final r = channel(c.red);
      final g = channel(c.green);
      final b = channel(c.blue);
      return 0.2126 * r + 0.7152 * g + 0.0722 * b;
    }

    double contrastRatio(Color c1, Color c2) {
      final l1 = relativeLuminance(c1);
      final l2 = relativeLuminance(c2);
      final lighter = max(l1, l2);
      final darker = min(l1, l2);
      return (lighter + 0.05) / (darker + 0.05);
    }

    test('All KiotViet status and branch badges achieve WCAG AA contrast (>= 4.5:1)', () {
      final badgePairs = <String, List<Color>>{
        'branchDongThang': [AppColors.branchDongThangText, AppColors.branchDongThangBg],
        'branchThoiBinh': [AppColors.branchThoiBinhText, AppColors.branchThoiBinhBg],
        'receiptCompleted': [AppColors.receiptCompletedText, AppColors.receiptCompletedBg],
        'receiptDraft': [AppColors.receiptDraftText, AppColors.receiptDraftBg],
        'receiptCancelled': [AppColors.receiptCancelledText, AppColors.receiptCancelledBg],
        'debtSettled': [AppColors.debtSettledText, AppColors.debtSettledBg],
        'debtSurplus': [AppColors.debtSurplusText, AppColors.debtSurplusBg],
        'attendanceOnTime': [AppColors.attendanceOnTimeText, AppColors.attendanceOnTimeBg],
        'attendanceLate': [AppColors.attendanceLateText, AppColors.attendanceLateBg],
        'attendanceEarlyLeave': [AppColors.attendanceEarlyLeaveText, AppColors.attendanceEarlyLeaveBg],
        'thumbDefault': [AppColors.thumbnailDefaultFg, AppColors.thumbnailDefaultBg],
        'thumbBlue': [AppColors.thumbnailBlueFg, AppColors.thumbnailBlueBg],
        'thumbPurple': [AppColors.thumbnailPurpleFg, AppColors.thumbnailPurpleBg],
        'thumbTeal': [AppColors.thumbnailTealFg, AppColors.thumbnailTealBg],
        'thumbAmber': [AppColors.thumbnailAmberFg, AppColors.thumbnailAmberBg],
        'thumbRed': [AppColors.thumbnailRedFg, AppColors.thumbnailRedBg],
        'thumbGreen': [AppColors.thumbnailGreenFg, AppColors.thumbnailGreenBg],
        'thumbRose': [AppColors.thumbnailRoseFg, AppColors.thumbnailRoseBg],
        'thumbSlate': [AppColors.thumbnailSlateFg, AppColors.thumbnailSlateBg],
      };

      for (final entry in badgePairs.entries) {
        final cr = contrastRatio(entry.value[0], entry.value[1]);
        expect(cr >= 4.5, isTrue,
            reason: '${entry.key} contrast ratio is $cr:1, expected >= 4.5:1 (WCAG AA)');
      }
    });

    test('Empirically detect low contrast in standard on<Status> combinations', () {
      // onPrimary (white) on primary (#0067AC) passes AA
      final crPrimary = contrastRatio(AppColors.onPrimary, AppColors.primary);
      expect(crPrimary >= 4.5, isTrue);

      // onSecondary (white) on secondary (#4EB848) fails AA (< 3.0:1)
      final crSecondary = contrastRatio(AppColors.onSecondary, AppColors.secondary);
      expect(crSecondary < 3.0, isTrue,
          reason: 'White text on KiotViet green (#4EB848) has poor contrast ($crSecondary:1 < 3.0:1)');

      // onSuccess (white) on success (#22C55E) fails AA (< 3.0:1)
      final crSuccess = contrastRatio(AppColors.onSuccess, AppColors.success);
      expect(crSuccess < 3.0, isTrue,
          reason: 'White text on success green (#22C55E) has poor contrast ($crSuccess:1 < 3.0:1)');

      // onWarning (white) on warning (#F59E0B) fails AA (< 3.0:1)
      final crWarning = contrastRatio(AppColors.onWarning, AppColors.warning);
      expect(crWarning < 3.0, isTrue,
          reason: 'White text on amber warning (#F59E0B) has poor contrast ($crWarning:1 < 3.0:1)');
    });

    test('Surface typography hierarchy achieves strong contrast against surfaceCard', () {
      expect(contrastRatio(AppColors.textPrimary, AppColors.surfaceCard) > 15.0, isTrue);
      expect(contrastRatio(AppColors.textHeadline, AppColors.surfaceCard) > 15.0, isTrue);
      expect(contrastRatio(AppColors.textTitle, AppColors.surfaceCard) > 14.0, isTrue);
      expect(contrastRatio(AppColors.textBodyDark, AppColors.surfaceCard) > 10.0, isTrue);
      expect(contrastRatio(AppColors.textMuted, AppColors.surfaceCard) >= 4.5, isTrue);
    });
  });

  group('Empirical Challenger M1: ARB Key Parity & Duplicate Detection', () {
    List<MapEntry<int, String>> findTopLevelDuplicateKeys(String filePath) {
      final file = File(filePath);
      final lines = file.readAsLinesSync();
      final seenKeys = <String>{};
      final duplicates = <MapEntry<int, String>>[];

      var depth = 0;
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        final trimmed = line.trim();

        if (depth == 1 && trimmed.startsWith('"')) {
          final parts = trimmed.split('"');
          if (parts.length >= 2) {
            final key = parts[1];
            if (seenKeys.contains(key)) {
              duplicates.add(MapEntry(i + 1, key));
            } else {
              seenKeys.add(key);
            }
          }
        }

        depth += '{'.allMatches(line).length;
        depth -= '}'.allMatches(line).length;
      }
      return duplicates;
    }

    test('Verify 0 duplicate top-level keys in app_vi.arb and app_en.arb', () {
      final viDuplicates = findTopLevelDuplicateKeys('lib/l10n/app_vi.arb');
      final enDuplicates = findTopLevelDuplicateKeys('lib/l10n/app_en.arb');

      final viDupKeys = viDuplicates.map((e) => e.value).toList();
      final enDupKeys = enDuplicates.map((e) => e.value).toList();

      // Confirm 0 duplicate keys remain
      expect(viDupKeys, isEmpty,
          reason: 'app_vi.arb contains duplicate keys: $viDuplicates');
      expect(enDupKeys, isEmpty,
          reason: 'app_en.arb contains duplicate keys: $enDuplicates');
    });

    test('Verify disambiguated semantic resolution of transfer and createdBy keys', () {
      final viParsed = jsonDecode(File('lib/l10n/app_vi.arb').readAsStringSync())
          as Map<String, dynamic>;
      final enParsed = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;

      expect(viParsed['transfer'], equals('Chuyển'));
      expect(viParsed['paymentMethodTransfer'], equals('Chuyển khoản'));
      expect(viParsed['createdBy'], equals('Người tạo'));
      expect(viParsed['orderCreatedBy'], equals('Người lập đơn'));
      expect(viParsed['profit'], equals('Lợi nhuận'));
      expect(viParsed['revenue'], equals('Doanh thu'));

      expect(enParsed['transfer'], equals('Transfer'));
      expect(enParsed['paymentMethodTransfer'], equals('Transfer'));
      expect(enParsed['createdBy'], equals('Created by'));
      expect(enParsed['orderCreatedBy'], equals('Order Creator'));
      expect(enParsed['profit'], equals('Profit'));
      expect(enParsed['revenue'], equals('Revenue'));
    });

    test('Verify full 100% key parity between app_vi.arb and app_en.arb (JSON representation)', () {
      final viMap = jsonDecode(File('lib/l10n/app_vi.arb').readAsStringSync())
          as Map<String, dynamic>;
      final enMap = jsonDecode(File('lib/l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;

      final viOnly = viMap.keys.toSet().difference(enMap.keys.toSet());
      final enOnly = enMap.keys.toSet().difference(viMap.keys.toSet());

      expect(viOnly, isEmpty, reason: 'Keys present only in app_vi.arb: $viOnly');
      expect(enOnly, isEmpty, reason: 'Keys present only in app_en.arb: $enOnly');
    });
  });

  group('Empirical Challenger M1: BuildContext.l10n Widget Context Invariants', () {
    testWidgets('context.l10n provides non-null AppLocalizations in Vietnamese locale',
        (tester) async {
      late AppLocalizations localizations;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              localizations = context.l10n;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(localizations, isNotNull);
      expect(localizations.localeName, equals('vi'));
      expect(localizations.commonContinue, equals('Tiếp tục'));
      expect(localizations.commonDraftReceipt, equals('Phiếu tạm'));
      expect(localizations.commonSaveDraft, equals('Lưu tạm'));
      expect(localizations.cancel, equals('Hủy'));
      expect(localizations.inventoryCreateReceipt, equals('Tạo phiếu nhập hàng'));

      // Confirm disambiguated localization values
      expect(localizations.transfer, equals('Chuyển'));
      expect(localizations.paymentMethodTransfer, equals('Chuyển khoản'));
      expect(localizations.createdBy, equals('Người tạo'));
      expect(localizations.orderCreatedBy, equals('Người lập đơn'));
      expect(localizations.profit, equals('Lợi nhuận'));
      expect(localizations.revenue, equals('Doanh thu'));
    });

    testWidgets('context.l10n provides non-null AppLocalizations in English locale',
        (tester) async {
      late AppLocalizations localizations;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              localizations = context.l10n;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(localizations, isNotNull);
      expect(localizations.localeName, equals('en'));
      expect(localizations.commonContinue, equals('Continue'));
      expect(localizations.commonDraftReceipt, equals('Draft Receipt'));
      expect(localizations.commonSaveDraft, equals('Save Draft'));
      expect(localizations.cancel, equals('Cancel'));
      expect(localizations.inventoryCreateReceipt, equals('Create Stock In Receipt'));

      // English resolved localization values
      expect(localizations.transfer, equals('Transfer'));
      expect(localizations.paymentMethodTransfer, equals('Transfer'));
      expect(localizations.createdBy, equals('Created by'));
      expect(localizations.orderCreatedBy, equals('Order Creator'));
      expect(localizations.profit, equals('Profit'));
      expect(localizations.revenue, equals('Revenue'));
    });

    testWidgets('context.l10n throws TypeError outside of Localizations tree',
        (tester) async {
      late dynamic thrownError;

      await tester.pumpWidget(
        Builder(
          builder: (context) {
            try {
              // Attempting to access context.l10n without Localizations delegate in scope
              final _ = context.l10n;
            } catch (e) {
              thrownError = e;
            }
            return const SizedBox.shrink();
          },
        ),
      );

      expect(thrownError, isA<TypeError>());
    });

    testWidgets('Parameterized getters handle diverse inputs gracefully without throwing',
        (tester) async {
      late AppLocalizations l10n;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) {
              l10n = context.l10n;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Stress test string and num placeholders
      expect(l10n.attendanceDeleteShiftConfirm(''), equals('Bạn có chắc muốn xóa ca ""?'));
      expect(l10n.attendanceDeleteShiftConfirm('Ca Đêm 23:00 - 07:00 (!@#)'),
          equals('Bạn có chắc muốn xóa ca "Ca Đêm 23:00 - 07:00 (!@#)"?'));
      expect(l10n.accountDeleteConfirm(''),
          equals('Bạn có chắc chắn muốn xóa tài khoản "" khỏi hệ thống? Hành động này không thể hoàn tác.'));
      expect(l10n.accountDeleteConfirm('admin_001 <root>'),
          equals('Bạn có chắc chắn muốn xóa tài khoản "admin_001 <root>" khỏi hệ thống? Hành động này không thể hoàn tác.'));
      expect(l10n.invoiceCountLabel(0), equals('0 hoá đơn'));
      expect(l10n.invoiceCountLabel(999999), equals('999999 hoá đơn'));
      expect(l10n.ordersCount(0), equals('(0 đơn)'));
      expect(l10n.orderIdLabel('ORD-12345'), equals('Mã đơn: ORD-12345'));
    });
  });
}
