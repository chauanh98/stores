import 'package:flutter/material.dart';

/// Bảng mã màu chuẩn hoá KiotViet Design System cho KD Store
class AppColors {
  AppColors._();

  // ── 1. Brand Colors ──
  static const primary = Color(0xFF0067AC); // KiotViet Blue thương hiệu
  static const primaryLight = Color(0xFFE0F2FE); // Nền xanh thương hiệu nhạt
  static const primaryMedium = Color(0xFF0284C7); // Icon/Text selected
  static const primaryDark = Color(0xFF0369A1); // Primary đậm
  static const primaryAction =
      Color(0xFF2563EB); // Nút hành động chính (Tailwind Blue)
  static const onPrimary =
      Color(0xFFFFFFFF); // Text tương phản trên nền primary

  static const secondary = Color(0xFF4EB848); // KiotViet Green thương hiệu
  static const secondaryLight = Color(0xFFDCFCE7); // Nền xanh lá nhạt
  static const secondaryDark = Color(0xFF15803D); // Xanh lá đậm
  static const onSecondary = Color(0xFFFFFFFF); // Text trên nền secondary

  // ── 2. Semantic Status Colors ──
  // Success
  static const success = Color(0xFF22C55E);
  static const successLight = Color(0xFFDCFCE7);
  static const successMedium = Color(0xFF16A34A);
  static const successDark = Color(0xFF15803D);
  static const successBorder = Color(0xFFBBF7D0);
  static const successSubtle = Color(0xFFF0FDF4);
  static const onSuccess = Color(0xFFFFFFFF);

  // Warning & Pending & Draft
  static const warning = Color(0xFFF59E0B);
  static const warningLight = Color(0xFFFEF3C7);
  static const warningMedium = Color(0xFFD97706);
  static const warningDark = Color(0xFFB45309);
  static const warningDeep = Color(0xFF92400E);
  static const warningBorder = Color(0xFFFDE68A);
  static const warningSubtle = Color(0xFFFFFBEB);
  static const onWarning = Color(0xFFFFFFFF);
  static const pending = warning;
  static const pendingLight = warningLight;
  static const draft = warning;
  static const draftLight = warningLight;

  // Danger & Error & Cancelled
  static const danger = Color(0xFFEF4444);
  static const dangerLight = Color(0xFFFEE2E2);
  static const dangerMedium = Color(0xFFDC2626);
  static const dangerDark = Color(0xFFB91C1C);
  static const dangerDeep = Color(0xFFC62828);
  static const dangerBorder = Color(0xFFFECACA);
  static const dangerSubtle = Color(0xFFFEF2F2);
  static const dangerLightest = Color(0xFFFFEBEE);
  static const onDanger = Color(0xFFFFFFFF);
  static const cancelled = danger;
  static const cancelledLight = dangerLight;

  // Info
  static const info = Color(0xFF0284C7);
  static const infoLight = Color(0xFFE0F2FE);
  static const infoDark = Color(0xFF0369A1);
  static const infoBorder = Color(0xFFBFDBFE);
  static const infoSubtle = Color(0xFFEFF6FF);
  static const onInfo = Color(0xFFFFFFFF);

  // Roles & Supervisor
  static const supervisor = Color(0xFF8B5CF6);
  static const supervisorLight = Color(0xFFF3E8FF);
  static const supervisorDark = Color(0xFF7B1FA2);

  // ── 3. Neutral & Surface Grayscale ──
  static const white = Color(0xFFFFFFFF);
  static const white70 = Color(0xB3FFFFFF);
  static const transparent = Color(0x00000000);
  static const black = Color(0xFF000000);
  static const overlay = Color(0x80000000); // 50% opacity backdrop
  static const scrim = Color(0x52000000); // 32% opacity modal

  static const background = Color(0xFFF4F6F9); // Nền Scaffold chính
  static const surface = Color(0xFFF8FAFC); // Nền Page phụ, input
  static const surfaceLight = Color(0xFFF1F5F9); // Nền Card nhạt
  static const surfaceCard = Color(0xFFFFFFFF); // Nền Card trắng chuẩn
  static const cardBackground = Color(0xFFFFFFFF); // Nền Card trắng
  static const surfaceContainer =
      Color(0xFFF0F4F8); // Surface container Material 3
  static const surfaceHighlight = Color(0xFFE0F2FE); // Nền mục được chọn
  static const surfaceInfo = Color(0xFFE3F2FD); // Nền badge tin tức

  // Slate Neutrals
  static const grey50 = Color(0xFFF9FAFB);
  static const grey100 = Color(0xFFF3F4F6);
  static const grey200 = Color(0xFFE5E7EB);
  static const grey300 = Color(0xFFD1D5DB);
  static const grey400 = Color(0xFF9CA3AF);
  static const grey500 = Color(0xFF6B7280);
  static const grey600 = Color(0xFF4B5563);
  static const grey700 = Color(0xFF374151);
  static const grey800 = Color(0xFF1F2937);
  static const grey900 = Color(0xFF111827);

  // Borders & Dividers
  static const border = Color(0xFFE1E2E4);
  static const borderLight = Color(0xFFE2E8F0);
  static const borderSubtle = Color(0xFFCBD5E1);
  static const divider = Color(0xFFEEEEEE);
  static const dividerLight = Color(0xFFF0F0F0);
  static const dividerSubtle = Color(0xFFF1F5F9);

  // Typography
  static const textPrimary = Color(0xFF1A1C1E);
  static const textSecondary = Color(0xFF73777F);
  static const textTertiary = Color(0xFF5C6066);
  static const textHeadline = Color(0xFF0F172A); // Slate 900
  static const textTitle = Color(0xFF1E293B); // Slate 800
  static const textBodyDark = Color(0xFF334155); // Slate 700
  static const textSlate600 = Color(0xFF475569); // Slate 600
  static const textMuted = Color(0xFF64748B); // Slate 500
  static const textDisabled = Color(0xFF94A3B8); // Slate 400

  // ── 4. KiotViet Badges & Cards ──
  // Branch Badges
  static const branchDongThangText = Color(0xFF0067AC);
  static const branchDongThangBg = Color(0xFFE0F2FE);
  static const branchDongThangBorder = Color(0xFFBAE6FD);

  static const branchThoiBinhText = Color(0xFF15803D);
  static const branchThoiBinhBg = Color(0xFFDCFCE7);
  static const branchThoiBinhBorder = Color(0xFFBBF7D0);

  // Receipt & Order Status Badges
  static const receiptCompletedText = Color(0xFF15803D);
  static const receiptCompletedBg = Color(0xFFDCFCE7);
  static const receiptCompletedBorder = Color(0xFFBBF7D0);

  static const receiptDraftText = Color(0xFFB45309);
  static const receiptDraftBg = Color(0xFFFEF3C7);
  static const receiptDraftBorder = Color(0xFFFDE68A);

  static const receiptCancelledText = Color(0xFFB91C1C);
  static const receiptCancelledBg = Color(0xFFFEE2E2);
  static const receiptCancelledBorder = Color(0xFFFECACA);

  // Debt Badges
  static const debtOwingText = Color(0xFFDC2626); // Khách nợ cửa hàng
  static const debtOwingBg = Color(0xFFFEE2E2);
  static const debtSettledText = Color(0xFF15803D); // Hết nợ / Đã thanh toán
  static const debtSettledBg = Color(0xFFDCFCE7);
  static const debtSurplusText = Color(0xFF0067AC); // Trả thừa / Nợ khách
  static const debtSurplusBg = Color(0xFFE0F2FE);

  // Attendance Status Badges
  static const attendanceOnTimeText = Color(0xFF15803D);
  static const attendanceOnTimeBg = Color(0xFFDCFCE7);
  static const attendanceLateText = Color(0xFFB45309);
  static const attendanceLateBg = Color(0xFFFEF3C7);
  static const attendanceEarlyLeaveText = Color(0xFFC2410C);
  static const attendanceEarlyLeaveBg = Color(0xFFFFEDD5);

  // ── 5. Analytics & Chart Colors ──
  static const chartBlue = Color(0xFF0067AC);
  static const chartLightBlue = Color(0xFF38BDF8);
  static const chartGreen = Color(0xFF22C55E);
  static const chartOrange = Color(0xFFF39C12);
  static const chartPurple = Color(0xFF9B59B6);
  static const chartRed = Color(0xFFE74C3C);
  static const chartTeal = Color(0xFF1ABC9C);
  static const chartYellow = Color(0xFFEAB308);
  static const chartIndigo = Color(0xFF6366F1);

  // Ranking Medals
  static const medalGold = Color(0xFFEAB308);
  static const medalSilver = Color(0xFF94A3B8);
  static const medalBronze = Color(0xFFB45309);

  // Custom UI Accents
  static const softBlueBorder = Color(0xFFCCE4FF);
  static const softBlueSurface = Color(0xFFF0F7FF);
  static const orangeLight = Color(0xFFFFF3E0);
  static const orangeDark = Color(0xFFEF6C00);
  static const purpleLight = Color(0xFFF3E5F5);
  static const purpleDark = Color(0xFF7B1FA2);
  static const tealLight = Color(0xFFCCFBF1);
  static const skyBorder = Color(0xFFBAE6FD);
  static const orange100 = Color(0xFFFFEDD5);
  static const orange700 = Color(0xFFC2410C);

  // ── 6. Product Image Thumbnail Pastel Palettes ──
  static const thumbnailDefaultBg = Color(0xFFEDF2F7);
  static const thumbnailDefaultFg = Color(0xFF4A5568);
  static const thumbnailBlueBg = Color(0xFFEBF8FF);
  static const thumbnailBlueFg = Color(0xFF2B6CB0);
  static const thumbnailPurpleBg = Color(0xFFFAF5FF);
  static const thumbnailPurpleFg = Color(0xFF6B46C1);
  static const thumbnailTealBg = Color(0xFFE6FFFA);
  static const thumbnailTealFg = Color(0xFF2C7A7B);
  static const thumbnailAmberBg = Color(0xFFFEFCBF);
  static const thumbnailAmberFg = Color(0xFF975A16);
  static const thumbnailRedBg = Color(0xFFFFF5F5);
  static const thumbnailRedFg = Color(0xFFC53030);
  static const thumbnailGreenBg = Color(0xFFF0FFF4);
  static const thumbnailGreenFg = Color(0xFF276749);
  static const thumbnailRoseBg = Color(0xFFFFF0F5);
  static const thumbnailRoseFg = Color(0xFFB83280);
  static const thumbnailSlateBg = Color(0xFFF7FAFC);
  static const thumbnailSlateFg = Color(0xFF4A5568);
}
