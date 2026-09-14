import 'package:flutter_test/flutter_test.dart';

import 'data_mau_verification_test.dart' as data_mau_e2e;
import 'tier1_feature_coverage_test.dart' as tier1;

import 'tier2_boundary_corner_test.dart' as tier2;
import 'tier3_cross_feature_test.dart' as tier3;
import 'tier4_real_world_scenarios_test.dart' as tier4;
import 'tier5_adversarial_domain_data_test.dart' as tier5_domain;
import 'tier5_adversarial_ui_lifecycle_test.dart' as tier5_ui;

/// Master E2E Test Suite Runner aggregating all E2E test tiers and data_mau.json verification.
///
/// Tiers included:
/// - Requirement R3: Real-World Ingestion & Verification with data_mau.json
/// - Tier 1: Feature Coverage (F1 to F9)
/// - Tier 2: Boundary & Corner Cases (F1 to F9)
/// - Tier 3: Pairwise & Cross-Feature Interactions
/// - Tier 4: Real-World Retail Application Scenarios
/// - Tier 5: Adversarial Hardening (Domain, FIFO, Data Serialization & UI/Lifecycle)
///
/// Execution commands:
/// - Full suite: `flutter test test/e2e/e2e_test_suite.dart`
/// - Data mau verification: `flutter test test/e2e/data_mau_verification_test.dart`
/// - Individual tiers: `flutter test test/e2e/tierX_..._test.dart`
void main() {
  group('=== MASTER E2E TEST SUITE: MULTI-BRANCH STORE SYNC & FIFO ENGINE ===', () {
    group('>>> REQUIREMENT R3: REAL-WORLD data_mau.json E2E VERIFICATION <<<', () {
      data_mau_e2e.main();
    });

    group('>>> TIER 1: FEATURE COVERAGE (F1 to F9) <<<', () {
      tier1.main();
    });

    group('>>> TIER 2: BOUNDARY & CORNER CASES (F1 to F9) <<<', () {
      tier2.main();
    });

    group('>>> TIER 3: CROSS-FEATURE & PAIRWISE INTERACTIONS <<<', () {
      tier3.main();
    });

    group('>>> TIER 4: REAL-WORLD RETAIL APPLICATION SCENARIOS <<<', () {
      tier4.main();
    });


    group('>>> TIER 5: ADVERSARIAL HARDENING (DOMAIN, FIFO & UI LIFECYCLE) <<<', () {
      group('Part A: Domain, FIFO & Serialization Adversarial Hardening', () {
        tier5_domain.main();
      });

      group('Part B: UI, State & Riverpod Lifecycle Adversarial Hardening', () {
        tier5_ui.main();
      });
    });
  });
}
