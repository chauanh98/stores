import 'package:flutter_test/flutter_test.dart';

import 'tier1_feature_coverage_test.dart' as tier1;
import 'tier2_boundary_corner_test.dart' as tier2;
import 'tier3_cross_feature_test.dart' as tier3;
import 'tier4_real_world_scenarios_test.dart' as tier4;
import 'tier5_adversarial_hardening_test.dart' as tier5;

void main() {
  group('====================================================================', () {
    group('=== MASTER SUITE: MOBILE STOCK-IN UPGRADE E2E VERIFICATION (R1-R4) ===', () {
      tier1.main();
      tier2.main();
      tier3.main();
      tier4.main();
      tier5.main();
    });
  });
}
