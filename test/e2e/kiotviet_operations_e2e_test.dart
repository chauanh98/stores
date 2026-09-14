import 'package:flutter_test/flutter_test.dart';

import 'kiotviet_tier1_feature_coverage_test.dart' as tier1;
import 'kiotviet_tier2_boundary_corner_test.dart' as tier2;
import 'kiotviet_tier3_cross_feature_test.dart' as tier3;
import 'kiotviet_tier4_real_world_scenarios_test.dart' as tier4;

/// Master Test Runner for KiotViet Operations Upgrade E2E Suite.
///
/// Features covered:
/// - R1: Customer Debt Filter & Navigation
/// - R2: Supplier Integration into Import Inventory & Debt Management
/// - R3: KPI Overview Interactive Drill-downs
/// - R4: Staff Shift Management & GPS Attendance System
///
/// Execution options:
/// - Run master runner:
///   `flutter test test/e2e/kiotviet_operations_e2e_test.dart`
/// - Run all E2E tests:
///   `flutter test test/e2e/`
void main() {
  group('=== MASTER E2E TEST TRACK: KIOTVIET OPERATIONS UPGRADE ===', () {
    group('>>> TIER 1: FEATURE COVERAGE (R1 - R4) <<<', () {
      tier1.main();
    });

    group('>>> TIER 2: BOUNDARY & CORNER CASES (R1 - R4) <<<', () {
      tier2.main();
    });

    group('>>> TIER 3: CROSS-FEATURE COMBINATIONS <<<', () {
      tier3.main();
    });

    group('>>> TIER 4: REAL-WORLD APPLICATION SCENARIOS <<<', () {
      tier4.main();
    });
  });
}
