import 'package:flutter_test/flutter_test.dart';

import '../support/orders_screens.dart';
import '../support/orders_support.dart';

void main() {
  final data = StressData.generate(envInt('STRESS_SEED', 20261014));
  registerMatrix(
      () => data, notificationScreens(), (u, d) => notificationOverrides(u, d));

  // Full device x text-scale cross product for the notification centre (cheap).
  for (final dev in devices) {
    for (final scale in textScales) {
      testWidgets('NotificationsPage full cross @ ${dev.name} x$scale',
          (tester) async {
        setView(tester, dev, 2);
        addTearDown(tester.view.reset);
        await withLog(tester, 'notifications ${dev.name} x$scale', (log) async {
          final screen = notificationScreens().first;
          await tester.pumpWidget(stressApp(screen.build(data),
              overrides: notificationOverrides(adminUser, data),
              textScale: scale));
          await tester.pumpAndSettle();
        });
      });
    }
  }
}
