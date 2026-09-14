import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/core/utils/invoice_print_helper.dart';
import 'package:stores/data/datasources/firebase/store_payment_config_remote_data_source.dart';
import 'package:stores/data/models/store_payment_config_model.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';
import 'package:stores/presentation/settings/pages/more_page.dart';
import 'package:stores/presentation/settings/pages/store_payment_settings_page.dart';

class _FakeAuthNotifier extends StateNotifier<UserAccount?>
    implements AuthNotifier {
  _FakeAuthNotifier(super.state);

  @override
  Future<String?> login(String username, String password) async => null;

  @override
  Future<void> logout() async {
    state = null;
  }
}

class _SpyStorePaymentConfigRemoteDataSource
    implements StorePaymentConfigRemoteDataSource {
  StorePaymentConfig? savedConfig;
  int saveCount = 0;

  @override
  Stream<StorePaymentConfig> watchConfig(String storeId) {
    return Stream.value(savedConfig ?? StorePaymentConfig(storeId: storeId));
  }

  @override
  Future<StorePaymentConfig> fetchConfig(String storeId) async {
    return savedConfig ?? StorePaymentConfig(storeId: storeId);
  }

  @override
  Future<void> saveConfig(StorePaymentConfig config) async {
    savedConfig = config;
    saveCount++;
  }
}

class _EmptyCustomerListNotifier extends CustomerListNotifier {
  @override
  Future<List<Customer>> build() async => [];
}

class _EmptySupplierListNotifier extends SupplierListNotifier {
  @override
  Future<List<Supplier>> build() async => [];
}

Widget _createTestWidget({
  required Widget child,
  List<Override> overrides = const [],
  Size size = const Size(800, 1400),
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: Material(child: child),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Adversarial Group 1: StorePaymentConfig Entity Edge Cases', () {
    test('Default values fallback check', () {
      const config = StorePaymentConfig(storeId: 'store_test');
      expect(config.storeId, 'store_test');
      expect(config.storeName, isNotEmpty);
      expect(config.paperSize, 'k80');
      expect(config.showVietQR, isTrue);
      expect(config.isK80, isTrue);
      expect(config.isK58, isFalse);
      expect(config.isA4, isFalse);
      expect(config.resolvedPageFormat, PdfPageFormat.roll80);
    });

    test('Case insensitivity and fallback for paperSize', () {
      const configUpperK80 = StorePaymentConfig(storeId: 's1', paperSize: 'K80');
      expect(configUpperK80.isK80, isTrue);
      expect(configUpperK80.resolvedPageFormat, PdfPageFormat.roll80);

      const configUpperK58 = StorePaymentConfig(storeId: 's1', paperSize: 'K58');
      expect(configUpperK58.isK58, isTrue);
      expect(configUpperK58.resolvedPageFormat, PdfPageFormat.roll57);

      const configUpperA4 = StorePaymentConfig(storeId: 's1', paperSize: 'A4');
      expect(configUpperA4.isA4, isTrue);
      expect(configUpperA4.resolvedPageFormat, PdfPageFormat.a4);

      // Unknown formats fallback to roll80
      const configUnknown = StorePaymentConfig(storeId: 's1', paperSize: 'letter');
      expect(configUnknown.isK80, isFalse);
      expect(configUnknown.isK58, isFalse);
      expect(configUnknown.isA4, isFalse);
      expect(configUnknown.resolvedPageFormat, PdfPageFormat.roll80);

      const configEmpty = StorePaymentConfig(storeId: 's1', paperSize: '');
      expect(configEmpty.resolvedPageFormat, PdfPageFormat.roll80);
    });

    test('fromMap with various malformed / partial JSON structures', () {
      // Null map
      final configNull = StorePaymentConfig.fromMap('store_null', null);
      expect(configNull.storeId, 'store_null');
      expect(configNull.paperSize, 'k80');
      expect(configNull.showVietQR, isTrue);

      // Empty map
      final configEmpty = StorePaymentConfig.fromMap('store_empty', {});
      expect(configEmpty.storeId, 'store_empty');
      expect(configEmpty.paperSize, 'k80');
      expect(configEmpty.showVietQR, isTrue);

      // Numeric inputs for string fields
      final configNumbers = StorePaymentConfig.fromMap('store_num', {
        'storeName': 12345,
        'phone': 917865300,
        'accountNo': 99998888,
        'paperSize': 'k58',
        'showVietQR': false,
      });
      expect(configNumbers.storeName, '12345');
      expect(configNumbers.phone, '917865300');
      expect(configNumbers.accountNo, '99998888');
      expect(configNumbers.paperSize, 'k58');
      expect(configNumbers.showVietQR, isFalse);

      // showVietQR as string "true" / "false"
      final configQrStrTrue = StorePaymentConfig.fromMap('s_qr', {'showVietQR': 'true'});
      expect(configQrStrTrue.showVietQR, isTrue);

      final configQrStrFalse = StorePaymentConfig.fromMap('s_qr', {'showVietQR': 'false'});
      expect(configQrStrFalse.showVietQR, isFalse);

      final configQrStrFalseCaps = StorePaymentConfig.fromMap('s_qr', {'showVietQR': 'FALSE'});
      expect(configQrStrFalseCaps.showVietQR, isFalse);
    });

    test('copyWith updates specific fields while keeping others intact', () {
      const original = StorePaymentConfig(
        storeId: 'store_orig',
        storeName: 'Cửa hàng A',
        address: 'Địa chỉ A',
        phone: '0123',
        bankName: 'VCB',
        bankId: 'vietcombank',
        accountNo: '1111',
        accountName: 'Nguyen A',
        footerNote: 'Note A',
        paperSize: 'k80',
        showVietQR: true,
      );

      final copy1 = original.copyWith(
        storeName: 'Cửa hàng B',
        paperSize: 'a4',
        showVietQR: false,
      );
      expect(copy1.storeId, 'store_orig');
      expect(copy1.storeName, 'Cửa hàng B');
      expect(copy1.address, 'Địa chỉ A');
      expect(copy1.paperSize, 'a4');
      expect(copy1.showVietQR, isFalse);

      final copyNoArgs = original.copyWith();
      expect(copyNoArgs, equals(original));
      expect(copyNoArgs.hashCode, equals(original.hashCode));
    });

    test('Value equality and hash code consistency', () {
      const a = StorePaymentConfig(storeId: 's1', paperSize: 'k80', showVietQR: true);
      const b = StorePaymentConfig(storeId: 's1', paperSize: 'k80', showVietQR: true);
      const c = StorePaymentConfig(storeId: 's1', paperSize: 'k80', showVietQR: false);
      const d = StorePaymentConfig(storeId: 's2', paperSize: 'k80', showVietQR: true);

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a, isNot(equals(d)));
    });
  });

  group('Adversarial Group 2: StorePaymentConfigModel DTO Edge Cases', () {
    test('Model serialization and deserialization with fallbackStoreId', () {
      final mapWithId = {
        'storeId': 'store_present',
        'storeName': 'Shop Present',
        'paperSize': 'k58',
        'showVietQR': false,
      };
      final modelWithId = StorePaymentConfigModel.fromMap(mapWithId, 'store_fallback');
      expect(modelWithId.storeId, 'store_present');
      expect(modelWithId.paperSize, 'k58');
      expect(modelWithId.showVietQR, isFalse);

      final mapWithoutId = {
        'storeName': 'Shop No ID',
      };
      final modelWithoutId = StorePaymentConfigModel.fromMap(mapWithoutId, 'store_fallback');
      expect(modelWithoutId.storeId, 'store_fallback');
      expect(modelWithoutId.storeName, 'Shop No ID');
      expect(modelWithoutId.paperSize, 'k80');
      expect(modelWithoutId.showVietQR, isTrue);

      final mapCompletelyEmpty = <dynamic, dynamic>{};
      final modelEmpty = StorePaymentConfigModel.fromMap(mapCompletelyEmpty);
      expect(modelEmpty.storeId, '');
      expect(modelEmpty.showVietQR, isTrue);
    });

    test('toDomain and fromDomain roundtrip fidelity', () {
      const entity = StorePaymentConfig(
        storeId: 'store_sync',
        storeName: 'Nội Thất Đồng Quê',
        address: 'Ấp 1, Xã Đông Thắng',
        phone: '0909999888',
        bankName: 'BIDV',
        bankId: 'bidv',
        accountNo: '666677778888',
        accountName: 'LE THI C',
        footerNote: 'Hẹn gặp lại quý khách!',
        paperSize: 'k58',
        showVietQR: false,
      );

      final model = StorePaymentConfigModel.fromDomain(entity);
      expect(model.storeId, entity.storeId);
      expect(model.paperSize, entity.paperSize);
      expect(model.showVietQR, entity.showVietQR);

      final backToDomain = model.toDomain();
      expect(backToDomain, equals(entity));
      expect(backToDomain.hashCode, equals(entity.hashCode));
    });

    test('Model copyWith and equality', () {
      const m1 = StorePaymentConfigModel(storeId: 's1', paperSize: 'k80');
      final m2 = m1.copyWith(paperSize: 'a4');
      expect(m2.paperSize, 'a4');
      expect(m2.storeId, 's1');

      const m3 = StorePaymentConfigModel(storeId: 's1', paperSize: 'k80');
      expect(m1, equals(m3));
      expect(m1.hashCode, equals(m3.hashCode));
    });
  });

  group('Adversarial Group 3: InvoicePrintHelper PDF Generation Stress Tests', () {
    final baseOrder = Order(
      id: 'HD_ADV_001',
      customerId: 'KH_ADV_01',
      createdAt: DateTime(2026, 8, 19, 14, 0),
      items: [
        OrderItem(
          productId: 'P1',
          productName: 'Tủ quần áo gỗ gõ đỏ 4 cánh phong cách cổ điển hoàng gia',
          quantity: 2,
          price: 18500000.0,
          warrantyMonths: 24,
          purchaseDate: DateTime(2026, 8, 19),
        ),
        OrderItem(
          productId: 'P2',
          productName: 'Giường ngủ bọc nệm cao cấp Queen Size 1m8 x 2m',
          quantity: 1,
          price: 12000000.0,
          warrantyMonths: 36,
          purchaseDate: DateTime(2026, 8, 19),
        ),
      ],
      total: 45000000.0, // Subtotal: 2*18.5M + 12M = 49M, discount 4M
      amountPaid: 30000000.0,
      debtAmount: 15000000.0,
      paymentMethod: 'split',
      cashAmount: 10000000.0,
      transferAmount: 20000000.0,
      note: 'Giao lầu 2, gọi trước 30 phút. Không bấm chuông giờ nghỉ trưa.',
    );

    const testCustomer = Customer(
      id: 'KH_ADV_01',
      name: 'Nguyễn Hoàng Gia Bảo',
      phone: '0988.777.666',
      email: 'giabao@example.com',
      address: 'Số 128/45 đường Nguyễn Văn Cừ Nối Dài, P. An Khánh, Q. Ninh Kiều, TP. Cần Thơ',
      purchases: [],
    );

    const baseConfig = StorePaymentConfig(
      storeId: 'store_001',
      storeName: 'TRANG TRÍ NỘI THẤT CAO CẤP KHÁNH ĐĂNG (CHI NHÁNH ĐÔNG THẮNG)',
      address: 'Khu thương mại Chợ Cờ Đỏ, Thị Trấn Cờ Đỏ, Huyện Cờ Đỏ, TP. Cần Thơ',
      phone: '0917.865 300 - 0939.865 300 - 02923.123.456',
      bankName: 'VIETINBANK CHI NHÁNH TÂY ĐÔ',
      bankId: 'icb',
      accountNo: '109876543210',
      accountName: 'HUYNH LE KHANH DANG',
      footerNote: 'QUÝ KHÁCH VUI LÒNG KIỂM TRA KỸ HÓA ĐƠN VÀ HÀNG HÓA TRƯỚC KHI RỜI CỬA HÀNG!',
      paperSize: 'k80',
      showVietQR: true,
    );

    void verifyPdfBytes(Uint8List bytes) {
      expect(bytes, isNotEmpty);
      expect(bytes.length, greaterThan(500));
      // Standard PDF header signature: %PDF-
      final header = ascii.decode(bytes.sublist(0, 5));
      expect(header, '%PDF-');
    }

    test('Matrix Test: K80 format with VietQR enabled', () async {
      final pdf = await InvoicePrintHelper.buildPdf(
        order: baseOrder,
        customer: testCustomer,
        config: baseConfig.copyWith(paperSize: 'k80', showVietQR: true),
      );
      verifyPdfBytes(pdf);
    });

    test('Matrix Test: K80 format with VietQR disabled', () async {
      final pdf = await InvoicePrintHelper.buildPdf(
        order: baseOrder,
        customer: testCustomer,
        config: baseConfig.copyWith(paperSize: 'k80', showVietQR: false),
      );
      verifyPdfBytes(pdf);
    });

    test('Matrix Test: K58 format with VietQR enabled', () async {
      final pdf = await InvoicePrintHelper.buildPdf(
        order: baseOrder,
        customer: testCustomer,
        config: baseConfig.copyWith(paperSize: 'k58', showVietQR: true),
      );
      verifyPdfBytes(pdf);
    });

    test('Matrix Test: K58 format with VietQR disabled', () async {
      final pdf = await InvoicePrintHelper.buildPdf(
        order: baseOrder,
        customer: testCustomer,
        config: baseConfig.copyWith(paperSize: 'k58', showVietQR: false),
      );
      verifyPdfBytes(pdf);
    });

    test('Matrix Test: A4 format with VietQR enabled', () async {
      final pdf = await InvoicePrintHelper.buildPdf(
        order: baseOrder,
        customer: testCustomer,
        config: baseConfig.copyWith(paperSize: 'a4', showVietQR: true),
      );
      verifyPdfBytes(pdf);
    });

    test('Matrix Test: A4 format with VietQR disabled', () async {
      final pdf = await InvoicePrintHelper.buildPdf(
        order: baseOrder,
        customer: testCustomer,
        config: baseConfig.copyWith(paperSize: 'a4', showVietQR: false),
      );
      verifyPdfBytes(pdf);
    });

    test('Stress Test: Long store name and multi-line notes in K58/K80/A4', () async {
      final longConfig = baseConfig.copyWith(
        storeName: 'TỔNG CÔNG TY THƯƠNG MẠI SẢN XUẤT XUẤT NHẬP KHẨU ĐỒ GỖ MỸ NGHỆ VIỆT NAM CAO CẤP VIP PRO MAX 2026',
        address: 'Tầng 12 Tòa nhà Landmark 81, 720A Điện Biên Phủ, Phường 22, Quận Bình Thạnh, Thành phố Hồ Chí Minh',
        footerNote: 'Cảm ơn quý khách đã tin tưởng và ủng hộ sản phẩm của chúng tôi. Mọi khiếu nại xin vui lòng liên hệ hotline trong vòng 7 ngày kể từ ngày nhận hàng.',
      );

      final longNoteOrder = baseOrder.copyWith(
        note: 'Giao vào cổng phụ sau 17h00.\n'
            'Yêu cầu mang dụng cụ lắp ráp vít 10mm.\n'
            'Khách muốn kiểm tra chất gỗ gõ đỏ trước khi thanh toán phần còn lại.',
      );

      for (final format in ['k80', 'k58', 'a4']) {
        final pdf = await InvoicePrintHelper.buildPdf(
          order: longNoteOrder,
          customer: testCustomer,
          config: longConfig.copyWith(paperSize: format),
        );
        verifyPdfBytes(pdf);
      }
    });

    test('Edge Case: Guest customer (khach_le) without customer entity', () async {
      final retailOrder = Order(
        id: 'HD_RETAIL_01',
        customerId: 'khach_le',
        createdAt: DateTime(2026, 8, 19, 15, 30),
        items: [
          OrderItem(
            productId: 'P99',
            productName: 'Chai xịt bóng gỗ cao cấp Pledge',
            quantity: 3,
            price: 85000.0,
            warrantyMonths: 0,
            purchaseDate: DateTime(2026, 8, 19),
          ),
        ],
        total: 255000.0,
        amountPaid: 255000.0,
        paymentMethod: 'cash',
      );

      for (final format in ['k80', 'k58', 'a4']) {
        final pdf = await InvoicePrintHelper.buildPdf(
          order: retailOrder,
          customer: null,
          config: baseConfig.copyWith(paperSize: format),
        );
        verifyPdfBytes(pdf);
      }
    });

    test('Edge Case: Zero discount order and Single Payment Method (Cash & Transfer)', () async {
      final cashOrder = Order(
        id: 'HD_CASH_01',
        customerId: 'KH01',
        createdAt: DateTime(2026, 8, 19),
        items: [
          OrderItem(
            productId: 'P1',
            productName: 'Sản phẩm thử nghiệm',
            quantity: 1,
            price: 500000.0,
            warrantyMonths: 0,
            purchaseDate: DateTime(2026, 8, 19),
          ),
        ],
        total: 500000.0, // Subtotal == Total (Zero discount)
        amountPaid: 500000.0,
        paymentMethod: 'cash',
      );

      final pdfCash = await InvoicePrintHelper.buildPdf(
        order: cashOrder,
        customer: null,
        config: baseConfig.copyWith(paperSize: 'k80'),
      );
      verifyPdfBytes(pdfCash);

      final transferOrder = cashOrder.copyWith(paymentMethod: 'transfer');
      final pdfTransfer = await InvoicePrintHelper.buildPdf(
        order: transferOrder,
        customer: null,
        config: baseConfig.copyWith(paperSize: 'a4'),
      );
      verifyPdfBytes(pdfTransfer);
    });

    test('Stress Test: High volume invoice with 20 items & Trillion VND amount', () async {
      final items = List.generate(
        20,
        (i) => OrderItem(
          productId: 'SP_$i',
          productName: 'Vật tư xây dựng hoàn thiện nội thất trọn gói lô số #$i',
          quantity: i + 1,
          price: 150000000.0,
          warrantyMonths: 12,
          purchaseDate: DateTime(2026, 8, 19),
        ),
      );

      final subtotal = items.fold(0.0, (sum, it) => sum + (it.price * it.quantity));
      final highVolOrder = Order(
        id: 'HD_BILLION_01',
        customerId: 'KH_CORP_01',
        createdAt: DateTime(2026, 8, 19),
        items: items,
        total: subtotal - 50000000.0,
        amountPaid: subtotal - 50000000.0,
        paymentMethod: 'transfer',
      );

      for (final format in ['k80', 'k58', 'a4']) {
        final pdf = await InvoicePrintHelper.buildPdf(
          order: highVolOrder,
          customer: testCustomer,
          config: baseConfig.copyWith(paperSize: format),
        );
        verifyPdfBytes(pdf);
      }
    });

    test('Edge Case: Overpaid order where amountPaid exceeds total', () async {
      final overpaidOrder = baseOrder.copyWith(
        total: 1000000.0,
        amountPaid: 1500000.0, // Remaining should be clamped to 0.0 without crashing
      );

      final pdf = await InvoicePrintHelper.buildPdf(
        order: overpaidOrder,
        customer: testCustomer,
        config: baseConfig.copyWith(paperSize: 'k80'),
      );
      verifyPdfBytes(pdf);
    });
  });

  group('Adversarial Group 4: Presentation Live Preview & Security RBAC Tests', () {
    const adminUser = UserAccount(
      username: 'boss',
      displayName: 'Chủ Cửa Hàng',
      role: 'admin',
      storeId: 'store_001',
    );

    const staffUser = UserAccount(
      username: 'sales01',
      displayName: 'Nhân Viên Bán Hàng',
      role: 'nhanvien',
      storeId: 'store_001',
    );

    const initialConfig = StorePaymentConfig(
      storeId: 'store_001',
      storeName: 'NỘI THẤT HOÀNG GIA ĐÔNG THẮNG',
      address: 'Chợ Đông Thắng',
      phone: '0917865300',
      bankName: 'VIETINBANK',
      bankId: 'vietinbank',
      accountNo: '0917865300',
      accountName: 'HUYNH LE KHANH DANG',
      footerNote: 'HÀNG ĐẢM BẢO CHẤT LƯỢNG',
      paperSize: 'k80',
      showVietQR: true,
    );

    testWidgets('Security RBAC: Staff is completely prevented from modifying receipt config',
        (tester) async {
      await tester.pumpWidget(
        _createTestWidget(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
            storePaymentConfigProvider.overrideWithValue(initialConfig),
          ],
          child: const StorePaymentSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Chỉ tài khoản Quản trị / Giám sát'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(Switch), findsNothing);
      expect(find.text('Lưu Cấu Hình Hóa Đơn'), findsNothing);
    });

    testWidgets('Admin interactivity: Live Preview updates synchronously on Paper Size chip selection',
        (tester) async {
      final spyDataSource = _SpyStorePaymentConfigRemoteDataSource();

      await tester.pumpWidget(
        _createTestWidget(
          overrides: [
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
            storePaymentConfigProvider.overrideWithValue(initialConfig),
            storePaymentConfigDataSourceProvider.overrideWithValue(spyDataSource),
          ],
          child: const StorePaymentSettingsPage(),
        ),
      );
      await tester.pumpAndSettle();

      // Initial tag should indicate K80
      expect(find.text('K80 (80mm)'), findsWidgets);

      // Select A4 chip
      await tester.tap(find.text('A4 (Chuẩn)'));
      await tester.pumpAndSettle();
      expect(find.text('A4 (Chuẩn)'), findsWidgets);

      // Select K58 chip
      await tester.tap(find.text('K58 (58mm)'));
      await tester.pumpAndSettle();
      expect(find.text('K58 (58mm)'), findsWidgets);

      // Toggle VietQR off
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      // Save configuration
      await tester.scrollUntilVisible(
        find.text('Lưu Cấu Hình Hóa Đơn'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Lưu Cấu Hình Hóa Đơn'));
      await tester.pumpAndSettle();

      expect(spyDataSource.saveCount, 1);
      expect(spyDataSource.savedConfig!.paperSize, 'k58');
      expect(spyDataSource.savedConfig!.showVietQR, isFalse);
    });

    testWidgets('MorePage Modern Dashboard: Admin views all 5 modern blocks and quick store switcher',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final commonOverrides = [
        currentStoreNameProvider.overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
        availableStoresProvider.overrideWith((ref) async => {
              'store_001': 'Chi nhánh Đông Thắng',
              'store_002': 'Chi nhánh Thới Bình',
            }),
        allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) => Stream.value(<Order>[])),
        customerListNotifierProvider.overrideWith(() => _EmptyCustomerListNotifier()),
        supplierListNotifierProvider.overrideWith(() => _EmptySupplierListNotifier()),
        productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
        accountsListProvider.overrideWith((ref) => Stream.value(<UserAccount>[adminUser])),
      ];

      await tester.pumpWidget(
        _createTestWidget(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _FakeAuthNotifier(adminUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      // Verify all 5 blocks exist
      expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsOneWidget); // Block 1
      expect(find.text('QUẢN LÝ ĐỐI TÁC'), findsOneWidget); // Block 2
      expect(find.text('NGHIỆP VỤ KHO & BÁN HÀNG'), findsOneWidget); // Block 3
      expect(find.text('CẤU HÌNH & QUẢN TRỊ'), findsOneWidget); // Block 4
      expect(find.text('HỆ THỐNG'), findsOneWidget); // Block 5
    });

    testWidgets('MorePage Modern Dashboard: Staff views limited blocks without Admin config or Store switcher',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final commonOverrides = [
        currentStoreNameProvider.overrideWith((ref) async => 'Chi nhánh Đông Thắng'),
        availableStoresProvider.overrideWith((ref) async => {
              'store_001': 'Chi nhánh Đông Thắng',
              'store_002': 'Chi nhánh Thới Bình',
            }),
        allBranchesOrdersByDateRangeProvider.overrideWith((ref, range) => Stream.value(<Order>[])),
        customerListNotifierProvider.overrideWith(() => _EmptyCustomerListNotifier()),
        supplierListNotifierProvider.overrideWith(() => _EmptySupplierListNotifier()),
        productListProvider.overrideWith((ref) => Stream.value(<Product>[])),
        accountsListProvider.overrideWith((ref) => Stream.value(<UserAccount>[staffUser])),
      ];

      await tester.pumpWidget(
        _createTestWidget(
          overrides: [
            ...commonOverrides,
            authProvider.overrideWith((ref) => _FakeAuthNotifier(staffUser)),
          ],
          child: const MorePage(),
        ),
      );
      await tester.pumpAndSettle();

      // Block 4 (Admin only) & Store switcher must be absent for Staff
      expect(find.text('CHUYỂN ĐỔI CỬA HÀNG'), findsNothing);
      expect(find.text('CẤU HÌNH & QUẢN TRỊ'), findsNothing);
      expect(find.text('Cấu hình VietQR'), findsNothing);
    });
  });
}
