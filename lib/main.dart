import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_theme.dart';
import 'package:stores/presentation/auth/pages/login_page.dart';
import 'package:stores/presentation/common/widgets/connection_status_banner.dart';
import 'package:stores/presentation/notifications/pages/notifications_page.dart';
import 'package:stores/presentation/orders/pages/invoices_page.dart';
import 'package:stores/presentation/orders/pages/pos_page.dart';
import 'package:stores/presentation/products/pages/products_page.dart';
import 'package:stores/presentation/reports/pages/overview_page.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';
import 'package:stores/application/notifications/local_notification_service.dart';
import 'package:stores/data/datasources/firebase/server_clock.dart';
import 'package:stores/presentation/notifications/utils/notification_tap_router.dart';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/core/services/filter_storage_service.dart';

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
  try {
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e) {
    debugPrint('FirebaseMessaging onBackgroundMessage initialization: $e');
  }
  try {
    FirebaseDatabase.instance.setPersistenceEnabled(false);
  } catch (e) {
    debugPrint('Firebase Database persistence initialization: $e');
  }
  // Độ lệch đồng hồ máy so với máy chủ (node cục bộ, không tốn băng thông).
  ServerClock.ensureStarted();
  final prefs = await SharedPreferences.getInstance();
  FilterStorageService.setSharedPrefs(prefs);
  setupFilterStorageResolver();
  runApp(ProviderScope(
    overrides: [
      filterStorageServiceProvider.overrideWith((ref) {
        return FilterStorageService(
          prefs,
          null,
          () {
            try {
              return ref.read(authProvider)?.username;
            } catch (_) {
              return null;
            }
          },
        );
      }),
    ],
    child: const MyApp(),
  ));
}

/// Navigator gốc — dùng để mở đúng màn hình khi người dùng bấm thông báo hệ thống.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(fcmTokenLifecycleManagerProvider);
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
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      themeMode: ThemeMode.light,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: user == null ? const LoginPage() : const AdaptiveScaffold(),
      routes: {
        '/notifications': (context) => const NotificationsPage(),
      },
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
  NotificationTapRouter? _tapRouter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final user = ref.read(authProvider);
      if (user != null && user.isAdmin) {
        ref.read(localNotificationServiceProvider).requestPermissions();
        ref.read(pushNotificationServiceProvider).requestPermissions();
        // Đăng ký token FCM do fcmTokenLifecycleManagerProvider đảm nhận
        // (đăng nhập, đổi chi nhánh, đăng xuất) — không ghi trùng ở đây.

        // Bấm thông báo hệ thống (kể cả khi app mở từ trạng thái tắt hẳn)
        // => mở đúng hoá đơn / phiếu nhập / khách hàng.
        _tapRouter = NotificationTapRouter(
          ref: ref,
          navigatorKey: appNavigatorKey,
        )..start();
      }
    });
  }

  @override
  void dispose() {
    _tapRouter?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider);
    if (user != null) {
      ref.watch(notificationListenerServiceProvider);
    }
    if (user != null && user.isAdmin) {
      ref.watch(fcmTokenLifecycleManagerProvider);
    }

    final isWideScreen = MediaQuery.of(context).size.width > 600;

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
          ? const ConnectionStatusBanner()
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ConnectionStatusBanner(),
                NavigationBar(
                  selectedIndex: _selectedIndex,
                  onDestinationSelected: (index) {
                    setState(() => _selectedIndex = index);
                  },
                  destinations: const [
                    NavigationDestination(
                        icon: Icon(Icons.trending_up),
                        selectedIcon: Icon(Icons.insights_rounded),
                        label: 'Tổng quan'),
                    NavigationDestination(
                        icon: Icon(Icons.inventory_2_outlined),
                        selectedIcon: Icon(Icons.inventory_2_rounded),
                        label: 'Hàng hoá'),
                    NavigationDestination(
                        icon: Icon(Icons.storefront_outlined),
                        selectedIcon: Icon(Icons.storefront_rounded),
                        label: 'Bán hàng'),
                    NavigationDestination(
                        icon: Icon(Icons.receipt_long_outlined),
                        selectedIcon: Icon(Icons.receipt_long_rounded),
                        label: 'Hoá đơn'),
                    NavigationDestination(
                        icon: Icon(Icons.menu),
                        selectedIcon: Icon(Icons.menu_open_rounded),
                        label: 'Nhiều hơn'),
                  ],
                ),
              ],
            ),
    );
  }
}
