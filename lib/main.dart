import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:stores/presentation/inventories/pages/imports_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/reports/pages/revenue_statistics_page.dart';
import 'package:stores/presentation/auth/pages/login_page.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/presentation/settings/pages/settings_page.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: user == null ? const LoginPage() : const AdaptiveScaffold(),
    );
  }
}

class AdaptiveScaffold extends ConsumerStatefulWidget {
  const AdaptiveScaffold({super.key});

  @override
  ConsumerState<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends ConsumerState<AdaptiveScaffold> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;
    final l10n = AppLocalizations.of(context)!;
    final user = ref.watch(authProvider);

    final screens = [
      const ImportsPage(key: PageStorageKey('imports')),
      const ProductsPage(key: PageStorageKey('products')),
      const CustomersPage(key: PageStorageKey('customers')),
      if (user?.isAdmin == true)
        const RevenueStatisticsPage(key: PageStorageKey('reports')),
      const SettingsPage(key: PageStorageKey('settings')),
    ];

    return Scaffold(
      body: Row(
        children: [
          if (isWideScreen)
            NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: [
                NavigationRailDestination(
                    icon: const Icon(Icons.dashboard),
                    label: Text(l10n.dashboard)),
                NavigationRailDestination(
                    icon: const Icon(Icons.shopping_bag),
                    label: Text(l10n.products)),
                NavigationRailDestination(
                    icon: const Icon(Icons.people),
                    label: Text(l10n.customers)),
                if (user?.isAdmin == true)
                  NavigationRailDestination(
                      icon: const Icon(Icons.bar_chart),
                      label: Text(l10n.reports)),
                const NavigationRailDestination(
                    icon: Icon(Icons.settings),
                    label: Text('Cài đặt')),
              ],
            ),
          Expanded(
            child: Column(
              children: [
                Container(
                  color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.store, size: 20),
                      const SizedBox(width: 8),
                      ref.watch(currentStoreNameProvider).when(
                        data: (name) => Text('Cửa hàng: $name', style: const TextStyle(fontWeight: FontWeight.bold)),
                        loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                        error: (_, __) => const Text('Lỗi tải tên cửa hàng'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _selectedIndex,
                    children: screens,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: isWideScreen
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) {
                setState(() => _selectedIndex = index);
              },
              destinations: [
                NavigationDestination(
                    icon: const Icon(Icons.dashboard), label: l10n.dashboard),
                NavigationDestination(
                    icon: const Icon(Icons.shopping_bag), label: l10n.products),
                NavigationDestination(
                    icon: const Icon(Icons.people), label: l10n.customers),
                if (user?.isAdmin == true)
                  NavigationDestination(
                      icon: const Icon(Icons.bar_chart), label: l10n.reports),
                const NavigationDestination(
                    icon: Icon(Icons.settings), label: 'Cài đặt'),
              ],
            ),
    );
  }
}
