// ignore_for_file: text_direction_code_point_in_literal
// Shared infrastructure for the large-data UI matrix + monkey stress tests
// (orders / inventories / notifications / common).
//
// Everything is deterministic: all data comes from a seeded [Gen].
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show FlutterExceptionHandler, FlutterError;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/application/customers/customer_list_notifier.dart';
import 'package:stores/application/customers/customers_providers.dart';
import 'package:stores/application/inventories/stock_in_receipts_providers.dart';
import 'package:stores/application/inventories/stock_transfer_providers.dart';
import 'package:stores/application/inventories/usecases/stock_transfer_use_cases.dart';
import 'package:stores/application/notifications/notifications_providers.dart';
import 'package:stores/application/orders/cart_providers.dart';
import 'package:stores/application/orders/orders_providers.dart';
import 'package:stores/application/products/categories_providers.dart';
import 'package:stores/application/products/products_providers.dart';
import 'package:stores/application/settings/store_payment_config_providers.dart';
import 'package:stores/application/suppliers/suppliers_providers.dart';
import 'package:stores/core/theme/app_theme.dart';
import 'package:stores/domain/entities/category.dart' as cat;
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/inventory_transaction.dart';
import 'package:stores/domain/entities/order.dart';
import 'package:stores/domain/entities/order_item.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/return_order.dart';
import 'package:stores/domain/entities/stock_transfer.dart';
import 'package:stores/domain/entities/store_payment_config.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/supplier_debt_transaction.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../../support/fake_rtdb.dart';

// ---------------------------------------------------------------------------
// Device matrix
// ---------------------------------------------------------------------------

class Device {
  const Device(this.name, this.w, this.h, {this.web = false});
  final String name;
  final double w;
  final double h;
  final bool web;
  Size get size => Size(w, h);
}

const devices = <Device>[
  Device('tiny 240x320', 240, 320),
  Device('foldable-cover 280x653', 280, 653),
  Device('small 320x568', 320, 568),
  Device('phone 360x640', 360, 640),
  Device('phone 390x844', 390, 844),
  Device('phone 412x915', 412, 915),
  Device('phone-land 915x412', 915, 412),
  Device('phone-land 844x390', 844, 390),
  Device('tablet-p 768x1024', 768, 1024),
  Device('tablet-l 1024x768', 1024, 768),
  Device('ipad-pro 1024x1366', 1024, 1366),
  Device('web 1280x720', 1280, 720, web: true),
  Device('web 1366x768', 1366, 768, web: true),
  Device('web 1440x900', 1440, 900, web: true),
  Device('web 1920x1080', 1920, 1080, web: true),
  Device('web 2560x1440', 2560, 1440, web: true),
  Device('ultrawide 3440x1440', 3440, 1440, web: true),
  Device('browser-narrow 480x800', 480, 800, web: true),
];

const textScales = <double>[0.8, 1.0, 1.3, 1.8, 2.0];
const dprs = <double>[1.0, 2.0, 3.0];

// ---------------------------------------------------------------------------
// Users / auth
// ---------------------------------------------------------------------------

class StressAuth extends StateNotifier<UserAccount?> implements AuthNotifier {
  StressAuth(super.state);
  @override
  Future<String?> login(String u, String p) async => null;
  @override
  Future<void> logout() async => state = null;
}

const adminUser = UserAccount(
    username: 'a',
    displayName: 'Quản trị viên có tên hiển thị rất dài để kiểm tra tràn',
    role: 'admin',
    storeId: 'store_001');
const staffUser = UserAccount(
    username: 's',
    displayName: 'Nhân viên Nguyễn Thị Thanh Thảo Quận Bình Thạnh',
    role: 'nhanvien',
    storeId: 'store_001');
const supervisorUser = UserAccount(
    username: 'g',
    displayName: 'Giám sát',
    role: 'supervisor',
    storeId: 'store_001');

const kStores = {
  'store_001': 'Chi nhánh Thành phố Hồ Chí Minh - Quận Bình Thạnh - Phường 25',
  'store_002': 'Chi nhánh Thới Bình',
};

const kConfig = StorePaymentConfig(
  storeId: 'store_001',
  storeName: 'Đông Thắng Store',
  address: '123 ĐT',
  phone: '0900000000',
  bankName: 'MBBank',
  bankId: 'mbbank',
  accountNo: '999988887777',
  accountName: 'TEST STORE',
  footerNote: 'Hẹn gặp lại',
);

// ---------------------------------------------------------------------------
// Seeded generator
// ---------------------------------------------------------------------------

class Gen {
  Gen(this.seed) : r = Random(seed);
  final int seed;
  final Random r;

  static final adversarial = <String>[
    // very long words, no spaces
    'Aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    'Nguyễn_Thị_Thanh_Thảo_Nguyên_Phương_Anh_Công_ty_TNHH_Nội_thất_Thành_phố_Hồ_Chí_Minh_Quận_Bình_Thạnh',
    'https://example.com/rat/dai/khong/co/khoang/trang/de/ngat/dong/abcdefghijklmnopqrstuvwxyz0123456789',
    // emoji + ZWJ sequences
    '🛒🔥 Combo 👨‍👩‍👧‍👦 khuyến mãi 🇻🇳🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉🎉',
    // combining (decomposed) Vietnamese + zalgo
    'Nguyễn Văn Ḍât́ Tống',
    'Z̀́̂̃̄̅̆̇̈̉̊̋̌̍̎̏̐à́̂̃̄̅̆̇̈l̀́̂̃go',
    // RTL
    'مرحبا بالعالم هذا اسم منتج طويل جدا للاختبار 123',
    'שלום עולם זהו שם מוצר ארוך מאוד לבדיקה',
    'Mixed עברית and English مع عربى 12345 and ‮override‬',
    // zero width
    'a​b‌c‍d⁠e﻿f‎‏',
    // newlines / tabs
    'Dòng 1\nDòng 2\n\n\nDòng 5\tTab\r\nCRLF',
    '   ',
    '',
    '<b>html</b> & "quotes" \'single\' \\ backslash %s {0}',
    '😀' * 80,
  ];

  String adv() => adversarial[r.nextInt(adversarial.length)];

  String name(int i) {
    switch (r.nextInt(6)) {
      case 0:
        return adv();
      case 1:
        return 'Bộ bàn ăn bên oval mặt nguyên tấm cực kỳ dài - 8 ghế bọc da cao cấp nhập khẩu màu nâu đậm $i';
      default:
        return 'Sản phẩm $i';
    }
  }

  static const moneyPool = <double>[
    0,
    1,
    0.5,
    -1,
    -123456,
    999,
    1000,
    1234567,
    99999999,
    123456789000,
    1e12,
    9.99e14,
  ];

  double money() => r.nextInt(5) == 0
      ? moneyPool[r.nextInt(moneyPool.length)]
      : (r.nextInt(5000) * 1000).toDouble();

  Product product(int i) => Product(
        id: 'p$i',
        name: name(i),
        code: r.nextInt(8) == 0 ? adv() : 'MA-$i',
        barcode: r.nextInt(3) == 0 ? null : '89300000$i',
        brand: r.nextBool() ? 'Thương hiệu Siêu Dài Quốc Tế Corp' : null,
        price: money(),
        costPrice: money().abs(),
        branchStocks: {
          'store_001': r.nextInt(10) == 0 ? -5 : r.nextInt(1000000),
          'store_002': r.nextInt(50),
        },
        category: r.nextBool()
            ? 'Bia, Rượu, Nước giải khát >> Nước ngọt có ga >> Lon 330ml nhập khẩu'
            : 'Danh mục ${i % 40}',
        unit: r.nextBool() ? 'Thùng' : null,
        minStock: r.nextInt(3) == 0 ? null : 10,
        allowSale: r.nextInt(20) != 0,
      );

  Customer customer(int i) => Customer(
        id: 'c$i',
        name: r.nextInt(5) == 0 ? adv() : 'Khách hàng $i Nguyễn Thị Thanh',
        phone: r.nextInt(6) == 0 ? '' : '09${10000000 + i}',
        email:
            r.nextBool() ? '' : 'khach.hang.$i@vi-du-ten-mien-dai.example.com',
        address: r.nextBool() ? '' : 'Số $i/45/6 Đường Nguyễn Văn Linh, Quận 7',
        purchases: const [],
        currentDebt: r.nextInt(3) == 0 ? money() : null,
      );

  OrderItem orderItem(int i, DateTime when) {
    final p = money().abs();
    return OrderItem(
      productId: 'p$i',
      productName: name(i),
      quantity: r.nextInt(8) == 0 ? 1000000 : 1 + r.nextInt(20),
      price: p,
      originalPrice: p,
      discount: r.nextInt(4) == 0 ? 5 : 0,
      isDiscountPercent: r.nextBool(),
      note: r.nextInt(4) == 0 ? adv() : '',
      warrantyMonths: r.nextInt(3) == 0 ? 12 : 0,
      purchaseDate: when,
    );
  }

  static const statuses = [
    'completed',
    'completed',
    'completed',
    'completed',
    'cancelled',
    'returned',
    'draft',
  ];

  Order order(int i, {int? lines, String? status, int customers = 1000}) {
    final when = DateTime(2026, 10, 14, 12)
        .subtract(Duration(minutes: i * 17 + r.nextInt(10)));
    final n = lines ?? (1 + r.nextInt(r.nextInt(10) == 0 ? 12 : 4));
    final items = [for (var k = 0; k < n; k++) orderItem(i * 7 + k, when)];
    final total = items.fold<double>(0, (s, e) => s + e.price * e.quantity);
    final st = status ?? statuses[r.nextInt(statuses.length)];
    final debt = r.nextBool() ? total / 3 : 0.0;
    final c = r.nextInt(customers);
    return Order(
      id: 'HD${100000 + i}',
      customerId: r.nextInt(10) == 0 ? '' : 'c$c',
      customerName: r.nextInt(10) == 0
          ? null
          : (r.nextInt(5) == 0 ? adv() : 'Khách hàng $c Nguyễn Thị Thanh'),
      customerPhone: r.nextInt(4) == 0 ? null : '09${10000000 + c}',
      createdAt: when,
      items: items,
      total: total,
      amountPaid: total - debt,
      debtAmount: debt,
      status: st,
      storeId: r.nextInt(8) == 0 ? 'store_002' : 'store_001',
      note: r.nextInt(3) == 0 ? adv() : null,
      createdByName: r.nextBool() ? staffUser.displayName : null,
      cancelReason: st == 'cancelled' ? adv() : null,
      cancelledAt: st == 'cancelled' ? when : null,
      cancelledByName: st == 'cancelled' ? adminUser.displayName : null,
      cashAmount: r.nextBool() ? total - debt : null,
      transferAmount: r.nextBool() ? 0 : null,
    );
  }

  ReturnOrder returnOrder(Order o, {int? lines}) {
    final n = lines ?? min(o.items.length, 100);
    final items = [
      for (var k = 0; k < n; k++)
        ReturnOrderItem(
            productId: 'p$k',
            productName: name(k),
            price: money().abs(),
            quantity: 1 + r.nextInt(5))
    ];
    return ReturnOrder(
      id: 'R${o.id}',
      orderId: o.id,
      customerId: o.customerId,
      customerName: o.customerName,
      storeId: 'store_001',
      createdAt: o.createdAt,
      items: items,
      totalReturnAmount: items.fold<double>(0, (s, e) => s + e.total),
      debtDeducted: money().abs(),
      cashRefunded: money().abs(),
      reason: adv(),
      createdByName: staffUser.displayName,
    );
  }

  StockInReceiptItem receiptItem(int i) => StockInReceiptItem(
        transactionId: 'tx$i',
        productId: 'p$i',
        quantity: r.nextInt(10) == 0 ? 1000000 : 1 + r.nextInt(100),
        importPrice: money().abs(),
        productName: name(i),
        productCode: r.nextInt(6) == 0 ? adv() : 'MA-$i',
        unit: r.nextBool() ? 'Hộp' : null,
        note: r.nextInt(5) == 0 ? adv() : '',
        discount: r.nextInt(5) == 0 ? 1000 : 0,
      );

  StockInReceipt receipt(int i, {int? lines, String? status}) {
    final n = lines ?? (1 + r.nextInt(6));
    final items = [for (var k = 0; k < n; k++) receiptItem(i * 3 + k)];
    final total = items.fold<double>(0, (s, e) => s + e.totalPrice);
    final paid = r.nextBool() ? total / 2 : total;
    return StockInReceipt(
      id: 'rec$i',
      importCode: 'PN_${20260101 + i}_${i.toString().padLeft(4, '0')}',
      date: DateTime(2026, 10, 14, 12).subtract(Duration(hours: i * 3)),
      storeId: r.nextInt(6) == 0 ? 'store_002' : 'store_001',
      supplierId: r.nextInt(5) == 0 ? null : 'sup${i % 50}',
      supplierName: r.nextInt(5) == 0
          ? null
          : (r.nextInt(4) == 0 ? adv() : 'Công ty Phân Bón Ánh Dương $i'),
      createdByName: r.nextBool() ? adminUser.displayName : null,
      note: r.nextInt(3) == 0 ? adv() : '',
      items: items,
      paidAmount: paid,
      debtAmount: total - paid,
      status: status ??
          const [
            'Đã nhập hàng',
            'Đã nhập hàng',
            'draft',
            'cancelled'
          ][r.nextInt(4)],
      cancelReason: null,
    );
  }

  StockTransfer transfer(int i,
      {int? lines, StockTransferStatus? status, int received = 0}) {
    final n = lines ?? (1 + r.nextInt(5));
    final st = status ??
        StockTransferStatus
            .values[r.nextInt(StockTransferStatus.values.length)];
    return StockTransfer(
      id: 'T$i',
      code: 'TRF${(100000 + i)}',
      status: st,
      sourceStoreId: 'store_001',
      sourceStoreName: kStores['store_001']!,
      targetStoreId: 'store_002',
      targetStoreName: 'Chi nhánh Thới Bình',
      createdAt: DateTime(2026, 10, 14, 10).subtract(Duration(hours: i)),
      createdByName: r.nextBool() ? 'Khánh Đăng' : null,
      note: r.nextInt(3) == 0 ? adv() : '',
      items: [
        for (var k = 0; k < n; k++)
          StockTransferItem(
              productId: 'p$k',
              name: name(k),
              code: r.nextInt(5) == 0 ? adv() : 'MA-$k',
              unitPrice: money().abs(),
              quantity: r.nextInt(8) == 0 ? 1000000 : 1 + r.nextInt(50),
              receivedQuantity: received),
      ],
    );
  }

  NotificationItem notification(int i) {
    const types = NotificationType.values;
    return NotificationItem(
      id: 'n$i',
      storeId: r.nextInt(5) == 0 ? 'store_002' : 'store_001',
      title: r.nextInt(4) == 0 ? adv() : 'Chuyển hàng #TRF${100000 + i}',
      body: r.nextInt(3) == 0
          ? adv()
          : '${money().toStringAsFixed(0)}đ - NCC: Công ty Phân Bón Ánh Dương (Lập bởi: Nguyễn Quản Trị) ' *
              (1 + r.nextInt(3)),
      type: types[r.nextInt(types.length)],
      isRead: r.nextInt(3) == 0,
      createdAt: DateTime(2026, 10, 14, 12).subtract(Duration(minutes: i * 11)),
      targetRoute: r.nextBool() ? 'transfer_detail' : null,
      targetId: 'T$i',
    );
  }
}

// ---------------------------------------------------------------------------
// Data sets (built once per test file; ~2000 invoices etc.)
// ---------------------------------------------------------------------------

class StressData {
  StressData._(this.seed)
      : g = Gen(seed),
        products = const [],
        customers = const [],
        orders = const [],
        receipts = const [],
        notifications = const [];

  final int seed;
  final Gen g;
  late List<Product> products;
  late List<Customer> customers;
  late List<Order> orders;
  late List<StockInReceipt> receipts;
  late List<NotificationItem> notifications;
  late List<StockTransfer> transfers;
  late Order bigOrder;
  late Order bigOrder300;
  late ReturnOrder bigReturn;
  late StockInReceipt bigReceipt;
  late StockTransfer bigTransfer;
  late List<Supplier> suppliers;

  factory StressData.generate(int seed,
      {int nOrders = 2000,
      int nProducts = 5000,
      int nCustomers = 1000,
      int nNotifications = 500,
      int nReceipts = 600}) {
    final d = StressData._(seed);
    final g = d.g;
    d.products = [for (var i = 0; i < nProducts; i++) g.product(i)];
    d.customers = [for (var i = 0; i < nCustomers; i++) g.customer(i)];
    d.orders = [
      for (var i = 0; i < nOrders; i++) g.order(i, customers: nCustomers)
    ];
    d.bigOrder = g.order(900001, lines: 150, status: 'completed');
    d.bigOrder300 = g.order(900002, lines: 300, status: 'completed');
    d.bigReturn = g.returnOrder(d.bigOrder, lines: 120);
    d.receipts = [for (var i = 0; i < nReceipts; i++) g.receipt(i)];
    d.bigReceipt = g.receipt(900003, lines: 250, status: 'Đã nhập hàng');
    d.transfers = [for (var i = 0; i < 300; i++) g.transfer(i)];
    d.bigTransfer =
        g.transfer(900004, lines: 200, status: StockTransferStatus.inTransit);
    d.notifications = [
      for (var i = 0; i < nNotifications; i++) g.notification(i)
    ];
    d.suppliers = [
      for (var i = 0; i < 50; i++)
        Supplier(
            id: 'sup$i',
            code: 'NCC$i',
            name: 'Công ty Phân Bón Ánh Dương $i',
            phone: '0901$i',
            currentDebt: g.money())
    ];
    return d;
  }
}

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

class StressCustomers extends AutoDisposeAsyncNotifier<List<Customer>>
    implements CustomerListNotifier {
  StressCustomers(this._list);
  final List<Customer> _list;
  @override
  Future<List<Customer>> build() async => _list;
  @override
  Future<void> refresh() async => state = AsyncValue.data(_list);
}

class StressSuppliers extends SupplierListNotifier {
  StressSuppliers(this._l);
  final List<Supplier> _l;
  @override
  Future<List<Supplier>> build() async => _l;
}

class FakeNotificationRepo implements NotificationRepository {
  final added = <NotificationItem>[];
  @override
  Stream<List<NotificationItem>> watchNotifications(String storeId,
          {int limit = 50}) =>
      const Stream.empty();
  @override
  Future<void> addNotification(NotificationItem n) async => added.add(n);
  @override
  Future<void> markAsRead(
      {required String storeId, required String id}) async {}
  @override
  Future<void> markAllAsRead(String storeId) async {}
  @override
  Future<void> deleteNotification(
      {required String storeId, required String id}) async {}
}

class FakeStockInRepo implements StockInReceiptRepository {
  @override
  Future<double?> getLatestImportPrice(
          {required String storeId, required String productId}) async =>
      120000;
  @override
  Future<String> saveDraft(StockInReceipt r) async => r.id;
  @override
  Future<void> updateDraft(StockInReceipt r) async {}
  @override
  Future<void> deleteDraft(
      {required String storeId, required String receiptId}) async {}
  @override
  Future<void> cancelReceipt(
      {required String storeId,
      required StockInReceipt receipt,
      required String reason,
      required String cancelledBy}) async {}
  @override
  Stream<List<StockInReceipt>> watchReceipts(String storeId) =>
      Stream.value([]);
  @override
  Future<List<StockInReceipt>> fetchReceipts(String storeId) async => [];
  @override
  Future<StockInReceipt?> getReceiptById(
          {required String storeId, required String receiptId}) async =>
      null;
  @override
  Future<void> saveReceipt(StockInReceipt r) async {}
  @override
  Future<void> deleteReceipt(
      {required String storeId, required String receiptId}) async {}
}

// ---------------------------------------------------------------------------
// Overrides
// ---------------------------------------------------------------------------

List<Override> baseOverrides(UserAccount user, StressData d) => [
      authProvider.overrideWith((ref) => StressAuth(user)),
      currentStoreIdProvider.overrideWith((ref) => 'store_001'),
      selectedPOSBranchProvider.overrideWith((ref) => 'store_001'),
      storePaymentConfigProvider.overrideWithValue(kConfig),
      productListProvider.overrideWith((ref) => Stream.value(d.products)),
      categoryListProvider.overrideWith((ref) => Stream.value(const [
            cat.Category(id: 'a', name: 'Danh mục có tên khá dài'),
            cat.Category(
                id: 'b', name: 'Phòng khách rất rộng lớn và sang trọng'),
          ])),
      accountsListProvider
          .overrideWith((ref) => Stream.value([adminUser, staffUser])),
      customerListNotifierProvider
          .overrideWith(() => StressCustomers(d.customers)),
      availableStoresProvider.overrideWith((ref) async => kStores),
    ];

List<Override> ordersOverrides(UserAccount user, StressData d,
        {List<Order>? orders, List<Order>? drafts}) =>
    [
      ...baseOverrides(user, d),
      allBranchesOrdersByDateRangeProvider
          .overrideWith((ref, range) => Stream.value(orders ?? d.orders)),
      posDraftOrdersProvider.overrideWith((ref) => Stream.value(drafts ??
          d.orders.where((o) => o.status == 'draft').take(60).toList())),
    ];

List<Override> inventoryOverrides(UserAccount user, StressData d,
    {List<StockInReceipt>? receipts, StockTransfer? single}) {
  final all = receipts ?? d.receipts;
  final transfers = d.transfers;
  final slip = single ?? transfers.first;
  final db = FakeRtdb();
  for (final t in [...transfers, d.bigTransfer]) {
    db.seed('stock_transfers/${t.id}', t.toMap());
  }
  final repo = FakeStockTransferRepository(db);
  return [
    ...baseOverrides(user, d),
    supplierListNotifierProvider
        .overrideWith(() => StressSuppliers(d.suppliers)),
    stockInReceiptsProvider.overrideWith((ref) => AsyncValue.data(all)),
    rawImportTransactionsStreamProvider
        .overrideWith((ref) => Stream.value(<InventoryTransaction>[])),
    storedStockInReceiptsStreamProvider
        .overrideWith((ref) => Stream.value(all)),
    allSupplierDebtTransactionsProvider
        .overrideWith((ref) => Stream.value(<SupplierDebtTransaction>[])),
    stockInReceiptRepositoryProvider.overrideWithValue(FakeStockInRepo()),
    stockTransfersProvider.overrideWith((ref) => Stream.value(transfers)),
    stockTransferByIdProvider.overrideWith((ref, id) => Stream.value(
        id == d.bigTransfer.id
            ? d.bigTransfer
            : transfers.firstWhere((t) => t.id == id, orElse: () => slip))),
    stockTransferRepositoryProvider.overrideWithValue(repo),
    receiveStockTransferUseCaseProvider
        .overrideWithValue(ReceiveStockTransferUseCase(db, repo, null)),
    cancelStockTransferUseCaseProvider
        .overrideWithValue(CancelStockTransferUseCase(db, repo, null)),
    createStockTransferUseCaseProvider
        .overrideWithValue(CreateStockTransferUseCase(db, repo, null)),
    saveStockTransferDraftUseCaseProvider
        .overrideWithValue(SaveStockTransferDraftUseCase(db, repo, null)),
  ];
}

List<Override> notificationOverrides(UserAccount user, StressData d) {
  final repo = FakeNotificationRepo();
  final unread = d.notifications.where((n) => !n.isRead).length;
  return [
    ...baseOverrides(user, d),
    notificationRepositoryProvider.overrideWithValue(repo),
    notificationStreamProvider
        .overrideWith((ref) => Stream.value(d.notifications)),
    popupNotificationStreamProvider
        .overrideWith((ref) => Stream.value(d.notifications)),
    unreadNotificationCountProvider.overrideWithValue(unread),
  ];
}

// ---------------------------------------------------------------------------
// Host / pump / error capture
// ---------------------------------------------------------------------------

Widget stressApp(Widget home,
    {ProviderContainer? container,
    List<Override> overrides = const [],
    double textScale = 1,
    bool dark = false,
    TextDirection? direction}) {
  final app = MaterialApp(
    debugShowCheckedModeBanner: false,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('vi'),
    theme: dark ? ThemeData.dark(useMaterial3: true) : AppTheme.lightTheme,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: direction == null
          ? child!
          : Directionality(textDirection: direction, child: child!),
    ),
    home: home,
  );
  if (container != null) {
    return UncontrolledProviderScope(container: container, child: app);
  }
  return ProviderScope(key: UniqueKey(), overrides: overrides, child: app);
}

Widget launcher(void Function(BuildContext) open) => Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: ElevatedButton(
            key: const Key('launch'),
            onPressed: () => open(ctx),
            child: const Text('open'),
          ),
        ),
      ),
    );

void setView(WidgetTester tester, Device d, double dpr) {
  tester.view.devicePixelRatio = dpr;
  tester.view.physicalSize = Size(d.w * dpr, d.h * dpr);
}

/// Errors that are environmental (no Firebase / platform plugins in unit
/// tests) and therefore intentionally ignored. Everything else fails.
bool isAllowedError(String text) {
  const allow = [
    'No Firebase App',
    'core/no-app',
    'Firebase has not been correctly initialized',
    'MissingPluginException',
    'FirebaseException',
    'FirebaseApp',
    'firebase_core',
    'PlatformException',
    'MobileScannerException', // camera plugin is unavailable in unit tests
    'LateInitializationError: Field \'_instance\'',
    'Bad state: No ProviderScope', // never expected
  ];
  // "No ProviderScope" is NOT environmental: do not allow it.
  return allow.where((a) => !a.startsWith('Bad state')).any(text.contains);
}

class ErrorLog {
  final List<String> errors = [];
  final List<String> ignored = [];
  FlutterExceptionHandler? _prev;

  void install() {
    _prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final full = d.toString();
      final text = '${d.exceptionAsString()}\n$full';
      final lines = full.split('\n');
      final k = lines.indexWhere((l) => l.contains('error-causing widget'));
      final where = RegExp(r'lib/presentation/[^\s:)]+:\d+')
          .allMatches(full)
          .map((m) => m.group(0))
          .toSet()
          .take(3)
          .join(', ');
      final head = d.exceptionAsString().split('\n').first;
      final frames = (d.stack?.toString() ?? '')
          .split('\n')
          .where((l) =>
              l.contains('lib/presentation') || l.contains('lib/application'))
          .map((l) => l.replaceAll(RegExp(r'^#\d+\s+'), '').trim())
          .take(3)
          .join(' <- ');
      final anyFrames = (d.stack?.toString() ?? '')
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) => l.replaceAll(RegExp(r'^#\d+\s+'), '').trim())
          .take(6)
          .join(' <- ');
      final detail =
          '$head @ ${k >= 0 ? lines.skip(k + 1).take(2).join(' ').trim() : ''} [$where] ${frames.isEmpty ? anyFrames : frames}';
      if (isAllowedError(text)) {
        ignored.add(head);
      } else {
        errors.add(detail);
      }
      // Forward to the test binding: errors that arrive through the zone's
      // uncaught-error path assert that the binding recorded them. They are
      // cleared again by [drain] (takeException) once classified here.
      _prev?.call(d);
    };
  }

  void uninstall() => FlutterError.onError = _prev;

  /// Records an error that escaped as an *unhandled async error* (e.g. a
  /// failed `await` in an `onPressed: () async {}` handler). Same allowlist.
  void addZoneError(Object e, StackTrace st) {
    final text = '$e\n$st';
    final head = e.toString().split('\n').first;
    if (isAllowedError(text)) {
      ignored.add('async: $head');
    } else {
      final frames = st
          .toString()
          .split('\n')
          .where((l) =>
              l.contains('lib/presentation') || l.contains('lib/application'))
          .map((l) => l.replaceAll(RegExp(r'^#\d+\s+'), '').trim())
          .take(3)
          .join(' <- ');
      final any = st
          .toString()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .take(6)
          .join(' <- ');
      errors.add(
          'unhandled async error: $head <- ${frames.isEmpty ? any : frames}');
    }
  }

  /// Clears the exceptions the binding recorded; every one of them already
  /// went through [install]'s handler and was classified there.
  void drain(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  List<String> unique() => errors.toSet().toList();
}

/// Registers an [ErrorLog] for the duration of a test.
ErrorLog trackErrors() {
  final log = ErrorLog()..install();
  addTearDown(log.uninstall);
  return log;
}

/// Pump & settle with a generous bound (some pages have infinite animations).
Future<void> settle(WidgetTester tester,
    {Duration step = const Duration(milliseconds: 100), int max = 40}) async {
  for (var i = 0; i < max; i++) {
    await tester.pump(step);
    if (!tester.binding.hasScheduledFrame) return;
  }
}

// ---------------------------------------------------------------------------
// Mouse / keyboard helpers (web)
// ---------------------------------------------------------------------------

Future<void> mouseHoverSweep(WidgetTester tester, {int points = 8}) async {
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  await g.addPointer(location: Offset.zero);
  for (var i = 1; i <= points; i++) {
    await g.moveTo(Offset(size.width * i / (points + 1),
        size.height * ((i * 3) % points + 1) / (points + 1)));
    await tester.pump(const Duration(milliseconds: 30));
  }
  await g.removePointer();
}

Future<void> wheelScroll(WidgetTester tester, double dy,
    {int times = 3}) async {
  final size = tester.view.physicalSize / tester.view.devicePixelRatio;
  final pos = Offset(size.width / 2, size.height / 2);
  final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await g.addPointer(location: pos);
  await g.moveTo(pos);
  for (var i = 0; i < times; i++) {
    await tester.sendEventToBinding(PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: pos,
        scrollDelta: Offset(0, dy)));
    await tester.pump(const Duration(milliseconds: 20));
  }
  await g.removePointer();
}

Future<void> keyboardTraverse(WidgetTester tester, {int tabs = 12}) async {
  for (var i = 0; i < tabs; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 10));
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pump(const Duration(milliseconds: 100));
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pump(const Duration(milliseconds: 100));
}

// ---------------------------------------------------------------------------
// Environment
// ---------------------------------------------------------------------------

int envInt(String key, int def) =>
    int.tryParse(Platform.environment[key] ?? '') ?? def;

/// Common assertion used by matrix tests.
void expectClean(ErrorLog log, String ctx) {
  if (log.unique().isNotEmpty) {
    fail('$ctx\n  - ${log.unique().join('\n  - ')}');
  }
}

/// Runs [body] with error capture; always restores the global handler (the
/// test binding asserts on that) and fails with the collected errors.
Future<void> withLog(WidgetTester tester, String ctx,
    Future<void> Function(ErrorLog log) body) async {
  final log = ErrorLog()..install();
  try {
    await body(log);
  } catch (_) {
    log.uninstall();
    log.drain(tester);
    if (log.errors.isNotEmpty) {
      fail('$ctx threw after errors:\n  - ${log.unique().join('\n  - ')}');
    }
    rethrow;
  }
  log.drain(tester);
  log.uninstall();
  expectClean(log, ctx);
}
