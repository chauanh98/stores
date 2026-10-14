import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/notifications/notification_visibility.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/notifications/pages/notifications_page.dart';

class _Auth extends StateNotifier<UserAccount?> implements AuthNotifier {
  _Auth(super.state);
  @override
  Future<String?> login(String u, String p) async => null;
  @override
  Future<void> logout() async => state = null;
}

const _long =
    'Khánh Đăng chuyển 12 mặt hàng (SL: 1000000) từ Chi nhánh Thành phố Hồ Chí Minh - Quận Bình Thạnh đến Chi nhánh Thới Bình rất dài';

List<NotificationItem> _items() => [
      for (var i = 0; i < 40; i++)
        NotificationItem(
          id: 'n$i',
          storeId: 'store_001',
          title: i.isEven ? 'Chuyển hàng #TRF${100000 + i}' : 'Hủy phiếu nhập kho #NK$i',
          body: i % 3 == 0 ? _long : '1.250.000.000đ - NCC: Công ty Phân Bón Ánh Dương (Lập bởi: Nguyễn Quản Trị)',
          type: [
            NotificationType.stockTransfer,
            NotificationType.inventoryImported,
            NotificationType.orderCreated,
            NotificationType.customerDebtAdded,
          ][i % 4],
          isRead: i % 5 == 0,
          createdAt: DateTime.now().subtract(Duration(minutes: i * 37)),
          targetRoute: 'transfer_detail',
          targetId: 'T$i',
        ),
    ];

const _screens = <String, Size>{
  '320x568': Size(320, 568),
  '360x640': Size(360, 640),
  '412x915': Size(412, 915),
  '768x1024': Size(768, 1024),
  '1280x800': Size(1280, 800),
};

void main() {
  const roles = {
    'admin': UserAccount(username: 'a', role: 'admin', storeId: 'all'),
    'supervisor':
        UserAccount(username: 'g', role: 'supervisor', storeId: 'store_001'),
    'nhanvien':
        UserAccount(username: 's', role: 'nhanvien', storeId: 'store_001'),
  };

  for (final screen in _screens.entries) {
    for (final scale in [1.0, 1.8]) {
      for (final role in roles.entries) {
        testWidgets(
            'NotificationsPage @ ${screen.key} x$scale as ${role.key}: no overflow, masked for staff',
            (tester) async {
          tester.view.physicalSize = screen.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final visible = notificationsForViewer(_items(), role.value);
          await tester.pumpWidget(ProviderScope(
            key: UniqueKey(),
            overrides: [
              authProvider.overrideWith((ref) => _Auth(role.value)),
              currentStoreIdProvider.overrideWithValue('store_001'),
              notificationStreamProvider
                  .overrideWith((ref) => Stream.value(visible)),
              popupNotificationStreamProvider
                  .overrideWith((ref) => Stream.value(visible)),
              unreadNotificationCountProvider.overrideWithValue(
                  visible.where((n) => !n.isRead).length),
            ],
            child: MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              locale: const Locale('vi'),
              builder: (c, child) => MediaQuery(
                data: MediaQuery.of(c)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: const NotificationsPage(),
            ),
          ));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (role.key == 'nhanvien') {
            // staff: no money anywhere, no debt notifications
            final texts = tester
                .widgetList<Text>(find.byType(Text))
                .map((t) => t.data ?? '')
                .join(' ');
            expect(RegExp(r'\d[\d.,]*\s?đ').hasMatch(texts), isFalse);
            expect(texts.contains('Ghi nhận nợ'), isFalse);
          }
          // scroll the whole list: lazy rows must not throw either
          await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        });
      }
    }
  }
}
