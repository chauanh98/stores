import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_theme.dart';
import 'package:stores/presentation/auth/pages/login_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/reports/pages/overview_page.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';

import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    // for iOS
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.dark,
  ));
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
    final isAuthLoading = ref.watch(authLoadingProvider);

    if (isAuthLoading) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
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
      const OverviewPage(key: PageStorageKey('overview')),
      const ProductsPage(key: PageStorageKey('products')),
      const POSPage(key: PageStorageKey('pos')),
      const InvoicesPage(key: PageStorageKey('invoices')),
      const MorePage(key: PageStorageKey('more')),
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
              destinations: const [
                NavigationRailDestination(
                    icon: Icon(Icons.trending_up), label: Text('Tổng quan')),
                NavigationRailDestination(
                    icon: Icon(Icons.inventory_2_outlined),
                    label: Text('Hàng hoá')),
                NavigationRailDestination(
                    icon: Icon(Icons.storefront_outlined),
                    label: Text('Bán hàng')),
                NavigationRailDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    label: Text('Hoá đơn')),
                NavigationRailDestination(
                    icon: Icon(Icons.menu), label: Text('Nhiều hơn')),
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
              destinations: const [
                NavigationDestination(
                    icon: Icon(Icons.trending_up), label: 'Tổng quan'),
                NavigationDestination(
                    icon: Icon(Icons.inventory_2_outlined), label: 'Hàng hoá'),
                NavigationDestination(
                    icon: Icon(Icons.storefront_outlined), label: 'Bán hàng'),
                NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined), label: 'Hoá đơn'),
                NavigationDestination(
                    icon: Icon(Icons.menu), label: 'Nhiều hơn'),
              ],
            ),
    );
  }
}
