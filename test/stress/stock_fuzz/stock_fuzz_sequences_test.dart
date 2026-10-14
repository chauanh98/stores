// Seeded random operation sequences against an independent reference model.
// STRESS_SEED / STRESS_ITER (number of sequences) control the run.
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'fuzz_runner.dart';
import 'fuzz_support.dart';

void main() {
  setUpAll(initFuzzLocale);

  test('random stock-in / transfer / POS sequences keep every invariant',
      () async {
    final sw = Stopwatch()..start();
    var totalOps = 0;
    final failures = <String>[];
    var seqCount = 0;
    for (var i = 0; i < stressIter; i++) {
      if (sw.elapsed.inSeconds > 50) break; // keep the file under ~60s
      seqCount++;
      final seed = stressSeed + i;
      final r = Random(seed);
      final h = Harness(threeBranches: seed % 3 == 2);
      final n = r.nextInt(5) == 0 ? 5 + r.nextInt(56) : 5 + r.nextInt(16);
      h.seedProducts(r, n);
      final runner = Runner(h, r);
      final ops = 6 + r.nextInt(20);
      Object? error;
      StackTrace? st;
      try {
        for (var k = 0; k < ops; k++) {
          await runner.step();
          if (h.violations.isNotEmpty) break;
        }
        if (h.violations.isEmpty) {
          h.checkAll(null, strictCrossView: !h.threeBranches);
        }
      } catch (e, s) {
        error = e;
        st = s;
      }
      totalOps += runner.opsRun;
      if (h.violations.isNotEmpty || error != null) {
        failures.add('seed=$seed (STRESS_SEED=$seed STRESS_ITER=1) '
            'three=${h.threeBranches}\n  violations: ${h.violations.take(4).join('\n    ')}'
            '${error != null ? '\n  error: $error\n$st' : ''}'
            '\n  last ops: ${h.log.reversed.take(6).toList().reversed.join(' | ')}');
        if (failures.length >= 8) break;
      }
    }
    // ignore: avoid_print
    print('stock fuzz: $seqCount sequences, $totalOps ops in '
        '${sw.elapsed.inMilliseconds}ms, ${failures.length} failing');
    expect(failures, isEmpty, reason: failures.join('\n----\n'));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
