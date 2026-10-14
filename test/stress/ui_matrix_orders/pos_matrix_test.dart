import '../support/orders_screens.dart';
import '../support/orders_support.dart';

void main() {
  final data = StressData.generate(envInt('STRESS_SEED', 20261014));
  registerMatrix(() => data, posScreens(), (u, d) => ordersOverrides(u, d));
}
