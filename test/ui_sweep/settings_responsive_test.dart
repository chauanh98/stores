import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventories/stock_transfer_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/settings/pages/account_management_page.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';
import 'package:stores/presentation/settings/pages/store_payment_settings_page.dart';

import 'sweep_harness.dart';

class _Customers extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

class _Suppliers extends SupplierListNotifier {
  @override
  Future<List<Supplier>> build() async => [];
}

List<UserAccount> _accounts(int n) => [
      for (var i = 0; i < n; i++)
        UserAccount(
            username: 'tai_khoan_co_ten_dang_nhap_rat_dai_$i',
            displayName:
                'Nguyễn Thị Thanh Thảo Hoàng Gia Bảo Châu Quận Bình Thạnh $i',
            role: ['admin', 'supervisor', 'nhanvien'][i % 3],
            storeId:
                i % 3 == 0 ? 'all' : (i.isEven ? 'store_001' : 'store_002')),
    ];

const _config = StorePaymentConfig(
  storeId: 'store_001',
  storeName:
      'TRANG TRÍ NỘI THẤT KHÁNH ĐĂNG - CHI NHÁNH THÀNH PHỐ HỒ CHÍ MINH QUẬN BÌNH THẠNH',
  address:
      'Chợ Cờ Đỏ, Xã Cờ Đỏ, Huyện Cờ Đỏ, Thành phố Cần Thơ, Việt Nam - gần ngã tư lớn',
  phone: '0917.865 300',
  bankName: 'VIETINBANK',
  bankId: 'vietinbank',
  accountNo: '0917865300123456789',
  accountName: 'Huỳnh Lê Khánh Đăng Nguyễn Thị Thanh Thảo',
  footerNote:
      'HÀNG ĐẢM BẢO ĐÚNG CHẤT LƯỢNG - ĐỔI TRẢ TRONG 7 NGÀY NẾU CÓ LỖI NHÀ SẢN XUẤT',
  paperSize: 'k80',
  showVietQR: true,
);

List<Override> _ov(UserAccount user, {int accounts = 40, bool error = false}) =>
    [
      authProvider.overrideWith((ref) => SweepAuth(user)),
      currentStoreIdProvider.overrideWithValue('store_001'),
      currentStoreNameProvider.overrideWith((ref) async => sweepLongStore),
      availableStoresProvider.overrideWith((ref) async => {
            'store_001': sweepLongStore,
            'store_002': 'Chi nhánh Thới Bình',
          }),
      allBranchesOrdersByDateRangeProvider
          .overrideWith((ref, range) => Stream.value(<Order>[])),
      customerListNotifierProvider.overrideWith(() => _Customers()),
      supplierListNotifierProvider.overrideWith(() => _Suppliers()),
      productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
      allStoresProductsProvider
          .overrideWith((ref) => Stream.value(<Product>[])),
      pendingIncomingTransferCountProvider
          .overrideWith((ref) => Stream.value(1234567)),
      accountsListProvider.overrideWith((ref) => error
          ? Stream<List<UserAccount>>.error('boom')
          : Stream.value(_accounts(accounts))),
      storePaymentConfigProvider.overrideWithValue(_config),
    ];

void main() {
  final small = {'320x568': sweepScreens['320x568']!};
  sweepMatrix('MorePage', () => const MorePage(), (u) => _ov(u));
  sweepMatrix('AccountManagementPage(40)', () => const AccountManagementPage(),
      (u) => _ov(u));
  sweepMatrix('AccountManagementPage(empty)',
      () => const AccountManagementPage(), (u) => _ov(u, accounts: 0),
      screens: small);
  sweepMatrix('AccountManagementPage(error)',
      () => const AccountManagementPage(), (u) => _ov(u, error: true),
      screens: small);
  sweepMatrix('StorePaymentSettingsPage',
      () => const StorePaymentSettingsPage(), (u) => _ov(u));

  testWidgets('AccountManagementPage with 400 accounts builds lazily',
      (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(sweepHost(
        const AccountManagementPage(), _ov(sweepAdmin, accounts: 400)));
    await tester.pumpAndSettle();
    expectNoException(tester);
    expect(find.textContaining('Nguyễn Thị Thanh Thảo').evaluate().length,
        lessThan(60));
  });
}
