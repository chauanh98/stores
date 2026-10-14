import '../support/orders_screens.dart';
import '../support/orders_support.dart';

void main() {
  final data = StressData.generate(envInt('STRESS_SEED', 20261014));
  registerMatrix(
      () => data, stockInScreens(), (u, d) => inventoryOverrides(u, d));
}
