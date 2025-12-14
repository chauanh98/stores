import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/presentation/customers/pages/customers_page.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:stores/presentation/inventories/pages/imports_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/reports/pages/revenue_statistics_page.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blue,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      // default: en
      home: const AdaptiveScaffold(),
    );
  }
}

class AdaptiveScaffold extends StatefulWidget {
  const AdaptiveScaffold({super.key});

  @override
  State<AdaptiveScaffold> createState() => _AdaptiveScaffoldState();
}

class _AdaptiveScaffoldState extends State<AdaptiveScaffold> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final isWideScreen = MediaQuery.of(context).size.width > 600;
    final l10n = AppLocalizations.of(context)!;

    final screens = [
      const ImportsPage(key: PageStorageKey('imports')),
      const ProductsPage(key: PageStorageKey('products')),
      const CustomersPage(key: PageStorageKey('customers')),
      const RevenueStatisticsPage(key: PageStorageKey('reports')),
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
                NavigationRailDestination(
                    icon: const Icon(Icons.bar_chart),
                    label: Text(l10n.reports)),
              ],
            ),
          Expanded(
            child: IndexedStack(
              index: _selectedIndex,
              children: screens,
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
                NavigationDestination(
                    icon: const Icon(Icons.bar_chart), label: l10n.reports),
              ],
            ),
    );
  }
}
