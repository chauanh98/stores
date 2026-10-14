import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/user_account.dart';

class SweepAuth extends StateNotifier<UserAccount?> implements AuthNotifier {
  SweepAuth(super.state);
  @override
  Future<String?> login(String u, String p) async => null;
  @override
  Future<void> logout() async => state = null;
}

const sweepAdmin = UserAccount(
    username: 'a',
    displayName: 'Quản trị viên có tên hiển thị rất dài để kiểm tra tràn',
    role: 'admin',
    storeId: 'store_001');
const sweepStaff = UserAccount(
    username: 's',
    displayName: 'Nhân viên Nguyễn Thị Thanh Thảo Quận Bình Thạnh',
    role: 'nhanvien',
    storeId: 'store_001');

const sweepLongName =
    'Bộ bàn ăn bên oval mặt nguyên tấm cực kỳ dài - 8 ghế bọc da cao cấp nhập khẩu màu nâu đậm';
const sweepLongStore =
    'Chi nhánh Thành phố Hồ Chí Minh - Quận Bình Thạnh - Phường 25';
const sweepHugeMoney = 123456789000.0;

const sweepScreens = <String, Size>{
  '320x568': Size(320, 568),
  '360x640': Size(360, 640),
  '412x915': Size(412, 915),
  '768x1024': Size(768, 1024),
  '1280x800': Size(1280, 800),
};

List<Product> sweepProducts(int n) => [
      for (var i = 0; i < n; i++)
        Product(
          id: 'p$i',
          name: i % 3 == 0 ? '$sweepLongName $i' : 'Sản phẩm $i',
          code: 'MA-$i-RAT-DAI-DE-KIEM-TRA',
          barcode: '89300000$i',
          brand: i % 2 == 0 ? 'Thương hiệu Siêu Dài Quốc Tế Corp' : 'Sabeco',
          price: sweepHugeMoney,
          costPrice: 99999999999,
          branchStocks: const {'store_001': 999999, 'store_002': 5},
          category: i % 2 == 0
              ? 'Bia, Rượu, Nước giải khát >> Nước ngọt có ga >> Lon 330ml nhập khẩu'
              : 'Đồ uống',
          minStock: 10,
        ),
    ];

Widget sweepHost(Widget home, List<Override> overrides,
    {double textScale = 1}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: home,
    ),
  );
}

/// Registers the screen x scale x role matrix for one page.
void sweepMatrix(
  String name,
  Widget Function() page,
  List<Override> Function(UserAccount user) overrides, {
  Map<String, Size> screens = sweepScreens,
}) {
  for (final s in screens.entries) {
    for (final scale in [1.0, 1.8]) {
      for (final user in [sweepAdmin, sweepStaff]) {
        testWidgets('$name @ ${s.key} x$scale ${user.role}', (tester) async {
          tester.view.physicalSize = s.value;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          debugSweepErrors();
          await tester
              .pumpWidget(sweepHost(page(), overrides(user), textScale: scale));
          await tester.pumpAndSettle();
          expectNoException(tester);
        });
      }
    }
  }
}

/// Fails with the full (creator-bearing) description of the first exception.
void expectNoException(WidgetTester tester) {
  final e = tester.takeException();
  if (e != null) {
    fail('Unexpected exception: ${e.toString().split('\n').first}');
  }
}

/// With SWEEP_DEBUG=1 prints the full details (creator chain) of each error.
void debugSweepErrors() {
  if (Platform.environment['SWEEP_DEBUG'] != '1') return;
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final lines = d.toString().split('\n');
    final k = lines.indexWhere((l) => l.contains('error-causing widget'));
    if (Platform.environment['SWEEP_FULL'] == '1') debugPrint(d.toString());
    debugPrint(
        'SWEEPERR ${lines.firstWhere((l) => l.contains('overflowed'), orElse: () => lines.first)} @ ${k >= 0 ? lines.skip(k + 1).take(2).join(' ') : ''}');
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}
