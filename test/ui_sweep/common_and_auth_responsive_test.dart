import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/presentation/auth/pages/login_page.dart';
import 'package:stores/presentation/common/widgets/connection_status_banner.dart';
import 'package:stores/presentation/common/widgets/date_grouped_list_view.dart';
import 'package:stores/presentation/common/widgets/empty_state_view.dart';
import 'package:stores/presentation/common/widgets/error_view.dart';
import 'package:stores/presentation/common/widgets/product_image_thumbnail.dart';
import 'package:stores/presentation/common/widgets/scroll_aware_fab.dart';

import 'sweep_harness.dart';

const _longError = 'FirebaseException: permission-denied rất dài ' +
    'xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx';

List<Override> _ov(user) =>
    [authProvider.overrideWith((ref) => SweepAuth(user))];

class _Item {
  _Item(this.i);
  final int i;
  DateTime get date => DateTime(2026, 9, 1).subtract(Duration(days: i ~/ 5));
}

void main() {
  sweepMatrix('LoginPage', () => const LoginPage(), (u) => []);

  sweepMatrix(
      'EmptyStateView(long)',
      () => EmptyStateView(
            icon: Icons.search_off,
            title: 'Không tìm thấy $sweepLongName trong danh sách hiện tại',
            message: 'Thử điều chỉnh bộ lọc hoặc từ khoá tìm kiếm ' * 5,
            actionLabel: 'Xoá bộ lọc và tải lại toàn bộ danh sách ngay',
            actionIcon: Icons.clear,
            onAction: () {},
          ),
      (u) => []);
  sweepMatrix('ErrorView(long)',
      () => ErrorView(Exception(_longError), onRetry: () {}), (u) => []);
  sweepMatrix('ConnectionStatusBanner',
      () => const Scaffold(body: ConnectionStatusBanner()), (u) => []);
  sweepMatrix(
      'DateGroupHeader(huge)',
      () => Scaffold(
            body: DateGroupHeader(
              date: DateTime(2026, 9, 1),
              itemCount: 9999999,
              itemUnit: 'giao dịch',
              totalAmount: sweepHugeMoney,
              currencyFormat: NumberFormat('#,###', 'vi_VN'),
              trailing: const Icon(Icons.chevron_right),
            ),
          ),
      (u) => []);
  sweepMatrix(
      'DateGroupedListView(300)',
      () => Scaffold(
            body: DateGroupedListView<_Item>(
              items: [for (var i = 0; i < 300; i++) _Item(i)],
              dateSelector: (i) => i.date,
              itemUnit: 'giao dịch',
              itemAmountSelector: (_) => sweepHugeMoney,
              itemBuilder: (c, i) =>
                  ListTile(title: Text('Mục $i $sweepLongName')),
            ),
          ),
      (u) => []);
  sweepMatrix(
      'ProductImageThumbnail',
      () => const Scaffold(
            body: Row(children: [
              ProductImageThumbnail(
                  imageUrl: 'data:image/png;base64,@@@',
                  productName: sweepLongName,
                  categoryName: 'Bia',
                  size: 48),
              ProductImageThumbnail(imageUrl: null, productName: ''),
            ]),
          ),
      (u) => []);

  testWidgets('DateGroupedListView with 3000 items builds lazily',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var built = 0;
    await tester.pumpWidget(sweepHost(
        Scaffold(
          body: DateGroupedListView<_Item>(
            items: [for (var i = 0; i < 3000; i++) _Item(i)],
            dateSelector: (i) => i.date,
            itemBuilder: (c, i) {
              built++;
              return SizedBox(height: 40, child: Text('Mục ${i.i}'));
            },
          ),
        ),
        []));
    await tester.pumpAndSettle();
    expectNoException(tester);
    expect(built, lessThan(120), reason: 'only visible + cache extent built');
  });

  testWidgets('ScrollAwareFab hides on scroll down and shows on scroll up',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(sweepHost(
        Scaffold(
          body: ListView.builder(
              controller: controller,
              itemCount: 200,
              itemBuilder: (c, i) => SizedBox(height: 50, child: Text('$i'))),
          floatingActionButton: ScrollAwareFab(
              scrollController: controller,
              child: FloatingActionButton(
                  onPressed: () {}, child: const Icon(Icons.add))),
        ),
        []));
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expectNoException(tester);
  });
}
