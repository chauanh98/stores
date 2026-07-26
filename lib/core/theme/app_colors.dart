import 'package:flutter/material.dart';

class AppColors {
  // ── Brand ──
  static const primary = Color(0xFF0067AC); // KiotViet Blue
  static const secondary = Color(0xFF4EB848); // KiotViet Green

  // ── Semantic Status Colors ──
  static const success = Color(0xFF22C55E); // Xanh lá thành công
  static const successLight = Color(0xFFDCFCE7); // Nền xanh lá nhẹ
  static const warning = Color(0xFFF59E0B); // Cam cảnh báo / Nhân viên
  static const warningLight = Color(0xFFFEF3C7); // Nền cam nhẹ
  static const danger = Color(0xFFEF4444); // Đỏ báo lỗi / Hủy đơn
  static const dangerLight = Color(0xFFFEE2E2); // Nền đỏ nhẹ
  static const supervisor = Color(0xFF8B5CF6); // Tím Giám sát
  static const supervisorLight = Color(0xFFF3E8FF); // Nền tím nhẹ

  // ── Surfaces ──
  static const background = Color(0xFFF4F6F9); // Nền chính
  static const surface = Color(0xFFF8FAFC); // Nền form / page phụ
  static const surfaceLight = Color(0xFFF1F5F9); // Nền card nhẹ
  static const surfaceHighlight = Color(0xFFE0F2FE); // Nền item được chọn
  static const surfaceInfo = Color(0xFFE3F2FD); // Nền badge thông tin

  // ── Borders & Dividers ──
  static const border = Color(0xFFE1E2E4); // Viền container chính
  static const borderLight = Color(0xFFE2E8F0); // Viền form input
  static const divider = Color(0xFFEEEEEE); // Phân cách chính
  static const dividerLight = Color(0xFFF0F0F0); // Phân cách nhẹ
  static const dividerSubtle = Color(0xFFF1F5F9); // Phân cách rất nhẹ
  static const surfaceContainer =
      Color(0xFFF0F4F8); // Surface container (theme)

  // ── Text ──
  static const textPrimary = Color(0xFF1A1C1E);
  static const textSecondary = Color(0xFF73777F);
  static const textTertiary = Color(0xFF5C6066); // Text phụ nhẹ hơn

  // ── Primary variants ──
  static const primaryDark = Color(0xFF0369A1); // Primary đậm (text selected)
  static const primaryMedium =
      Color(0xFF0284C7); // Primary trung (icon selected)

  // ── Chart colors ──
  static const chartOrange = Color(0xFFF39C12);
  static const chartPurple = Color(0xFF9B59B6);
  static const chartRed = Color(0xFFE74C3C);
  static const chartTeal = Color(0xFF1ABC9C);
}
