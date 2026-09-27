import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/theme/app_colors.dart';

void main() {
  group('AppColors Semantic Tokens Verification', () {
    test('Brand colors have correct values', () {
      expect(AppColors.primary, const Color(0xFF0067AC));
      expect(AppColors.secondary, const Color(0xFF4EB848));
      expect(AppColors.primaryAction, const Color(0xFF2563EB));
      expect(AppColors.onPrimary, const Color(0xFFFFFFFF));
      expect(AppColors.onSecondary, const Color(0xFFFFFFFF));
      expect(AppColors.primaryLight, const Color(0xFFE0F2FE));
      expect(AppColors.primaryDark, const Color(0xFF0369A1));
    });

    test('Semantic status colors and aliases are defined correctly', () {
      expect(AppColors.success, const Color(0xFF22C55E));
      expect(AppColors.warning, const Color(0xFFF59E0B));
      expect(AppColors.danger, const Color(0xFFEF4444));
      expect(AppColors.info, const Color(0xFF0284C7));
      expect(AppColors.supervisor, const Color(0xFF8B5CF6));

      // Status aliases
      expect(AppColors.pending, AppColors.warning);
      expect(AppColors.pendingLight, AppColors.warningLight);
      expect(AppColors.cancelled, AppColors.danger);
      expect(AppColors.cancelledLight, AppColors.dangerLight);
      expect(AppColors.draft, AppColors.warning);
      expect(AppColors.draftLight, AppColors.warningLight);
    });

    test('Neutral and surface grayscale tokens are defined correctly', () {
      expect(AppColors.white, const Color(0xFFFFFFFF));
      expect(AppColors.white70, const Color(0xB3FFFFFF));
      expect(AppColors.transparent, const Color(0x00000000));
      expect(AppColors.black, const Color(0xFF000000));
      expect(AppColors.background, const Color(0xFFF4F6F9));
      expect(AppColors.surface, const Color(0xFFF8FAFC));
      expect(AppColors.surfaceCard, const Color(0xFFFFFFFF));
      expect(AppColors.cardBackground, const Color(0xFFFFFFFF));
      expect(AppColors.border, const Color(0xFFE1E2E4));
      expect(AppColors.borderLight, const Color(0xFFE2E8F0));
      expect(AppColors.divider, const Color(0xFFEEEEEE));

      // Grey scales
      expect(AppColors.grey50, const Color(0xFFF9FAFB));
      expect(AppColors.grey100, const Color(0xFFF3F4F6));
      expect(AppColors.grey200, const Color(0xFFE5E7EB));
      expect(AppColors.grey300, const Color(0xFFD1D5DB));
      expect(AppColors.grey400, const Color(0xFF9CA3AF));
      expect(AppColors.grey500, const Color(0xFF6B7280));
      expect(AppColors.grey600, const Color(0xFF4B5563));
      expect(AppColors.grey700, const Color(0xFF374151));
      expect(AppColors.grey800, const Color(0xFF1F2937));
      expect(AppColors.grey900, const Color(0xFF111827));
    });

    test('Store branch badge tokens are defined correctly', () {
      expect(AppColors.branchDongThangText, const Color(0xFF0067AC));
      expect(AppColors.branchDongThangBg, const Color(0xFFE0F2FE));
      expect(AppColors.branchDongThangBorder, const Color(0xFFBAE6FD));

      expect(AppColors.branchThoiBinhText, const Color(0xFF15803D));
      expect(AppColors.branchThoiBinhBg, const Color(0xFFDCFCE7));
      expect(AppColors.branchThoiBinhBorder, const Color(0xFFBBF7D0));
    });

    test('Receipt and order status tokens are defined correctly', () {
      expect(AppColors.receiptCompletedText, const Color(0xFF15803D));
      expect(AppColors.receiptCompletedBg, const Color(0xFFDCFCE7));
      expect(AppColors.receiptCompletedBorder, const Color(0xFFBBF7D0));

      expect(AppColors.receiptDraftText, const Color(0xFFB45309));
      expect(AppColors.receiptDraftBg, const Color(0xFFFEF3C7));
      expect(AppColors.receiptDraftBorder, const Color(0xFFFDE68A));

      expect(AppColors.receiptCancelledText, const Color(0xFFB91C1C));
      expect(AppColors.receiptCancelledBg, const Color(0xFFFEE2E2));
      expect(AppColors.receiptCancelledBorder, const Color(0xFFFECACA));
    });

    test('Debt and attendance badges are defined correctly', () {
      expect(AppColors.debtOwingText, const Color(0xFFDC2626));
      expect(AppColors.debtSettledText, const Color(0xFF15803D));
      expect(AppColors.debtSurplusText, const Color(0xFF0067AC));

      expect(AppColors.attendanceOnTimeText, const Color(0xFF15803D));
      expect(AppColors.attendanceLateText, const Color(0xFFB45309));
      expect(AppColors.attendanceEarlyLeaveText, const Color(0xFFC2410C));
    });

    test('Analytics, charts and ranking medals are defined correctly', () {
      expect(AppColors.chartBlue, const Color(0xFF0067AC));
      expect(AppColors.chartGreen, const Color(0xFF22C55E));
      expect(AppColors.chartOrange, const Color(0xFFF39C12));
      expect(AppColors.chartPurple, const Color(0xFF9B59B6));
      expect(AppColors.chartRed, const Color(0xFFE74C3C));
      expect(AppColors.chartTeal, const Color(0xFF1ABC9C));
      expect(AppColors.chartYellow, const Color(0xFFEAB308));
      expect(AppColors.chartIndigo, const Color(0xFF6366F1));

      expect(AppColors.medalGold, const Color(0xFFEAB308));
      expect(AppColors.medalSilver, const Color(0xFF94A3B8));
      expect(AppColors.medalBronze, const Color(0xFFB45309));
    });

    test('Product thumbnail pastel palettes are defined correctly', () {
      expect(AppColors.thumbnailBlueBg, const Color(0xFFEBF8FF));
      expect(AppColors.thumbnailBlueFg, const Color(0xFF2B6CB0));
      expect(AppColors.thumbnailTealBg, const Color(0xFFE6FFFA));
      expect(AppColors.thumbnailTealFg, const Color(0xFF2C7A7B));
      expect(AppColors.thumbnailAmberBg, const Color(0xFFFEFCBF));
      expect(AppColors.thumbnailAmberFg, const Color(0xFF975A16));
    });
  });
}
