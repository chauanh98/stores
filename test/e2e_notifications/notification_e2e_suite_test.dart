import 'package:flutter_test/flutter_test.dart';

import 'tier1_feature_coverage_test.dart' as tier1;
import 'tier2_boundary_corner_test.dart' as tier2;
import 'tier3_cross_feature_pairwise_test.dart' as tier3;
import 'tier4_real_world_scenarios_test.dart' as tier4;

void main() {
  group('====================================================================', () {
    group('REALTIME IN-APP NOTIFICATION CENTER & LOCAL NOTIFICATIONS E2E SUITE', () {
      tier1.main();
      tier2.main();
      tier3.main();
      tier4.main();
    });
  });
}
