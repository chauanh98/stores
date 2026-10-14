// Shared kit for the "other" UI stress matrix + monkey tests:
// seeded data generator, device matrix, host, matrix registrar.
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/core/theme/app_theme.dart';
import 'package:stores/domain/entities/customer.dart';
import 'package:stores/domain/entities/product.dart';
import 'package:stores/domain/entities/revenue_report.dart';
import 'package:stores/domain/entities/supplier.dart';
import 'package:stores/domain/entities/user_account.dart';

import '../../ui_sweep/sweep_harness.dart'
    show SweepAuth, sweepAdmin, sweepStaff;

export '../../ui_sweep/sweep_harness.dart'
    show SweepAuth, sweepAdmin, sweepStaff, sweepLongStore;

int get stressSeed =>
    int.tryParse(Platform.environment['STRESS_SEED'] ?? '') ?? 20260101;
int stressIter([int def = 300]) =>
    int.tryParse(Platform.environment['STRESS_ITER'] ?? '') ?? def;

class Dev {
  const Dev(this.name, this.w, this.h, this.dpr);
  final String name;
  final double w, h, dpr;
  Size get logical => Size(w, h);
}

const devices = <Dev>[
  Dev('tiny240x320', 240, 320, 1),
  Dev('fold-cover280x653', 280, 653, 3),
  Dev('320x568', 320, 568, 2),
  Dev('360x640', 360, 640, 3),
  Dev('390x844', 390, 844, 3),
  Dev('412x915', 412, 915, 2.625),
  Dev('land915x412', 915, 412, 2.625),
  Dev('land844x390', 844, 390, 3),
  Dev('tabP768x1024', 768, 1024, 2),
  Dev('tabL1024x768', 1024, 768, 2),
  Dev('iPadPro1024x1366', 1024, 1366, 2),
  Dev('web1280x720', 1280, 720, 1),
  Dev('web1366x768', 1366, 768, 1),
  Dev('web1440x900', 1440, 900, 2),
  Dev('web1920x1080', 1920, 1080, 1),
  Dev('web2560x1440', 2560, 1440, 1),
  Dev('ultrawide3440x1440', 3440, 1440, 1),
  Dev('narrow480x800', 480, 800, 1),
];

const textScales = <double>[0.8, 1.0, 1.3, 1.8, 2.0];

void setDevice(WidgetTester t, Dev d) {
  t.view.devicePixelRatio = d.dpr;
  t.view.physicalSize = Size(d.w * d.dpr, d.h * d.dpr);
}

// ---------------------------------------------------------------- strings
const longWord =
    'SieuDaiKhongNgatTuKhongCoKhoangTrangDeKiemTraTranDong0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'
    'SieuDaiKhongNgatTuKhongCoKhoangTrangDeKiemTraTranDong0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const emojiStr = '😀🔥👨‍👩‍👧‍👦🇻🇳🏳️‍🌈 Hàng 🎉';
// decomposed (NFD) Vietnamese: e + circumflex + tilde, o + horn + dot-below
const combining = 'Nguyễn Thợ Hải';
const rtl = 'مرحبا بالعالم שלום עולם';
const zeroWidth = 'a​b‍c﻿d⁠e';
const newlines = 'dòng 1\n\n\ndòng 2\r\n\tthụt lề\n';

const adversarial = <String>[
  longWord,
  emojiStr,
  combining,
  rtl,
  zeroWidth,
  newlines,
  '   ',
  '',
  '<b>x</b> \'; DROP TABLE--',
  'Bộ bàn ăn bên oval mặt nguyên tấm cực kỳ dài - 8 ghế bọc da cao cấp nhập khẩu',
];

const amounts = <double>[0, -1, -123456789, 1e12, 99999999999, 0.5, 1, 1500];

// -------------------------------------------------------------- generator
class Gen {
  Gen([int? seed]) : r = Random(seed ?? stressSeed);
  final Random r;
  T pick<T>(List<T> l) => l[r.nextInt(l.length)];
  String adv() => pick(adversarial);
  String maybeAdv(String base, {double p = 0.15}) =>
      r.nextDouble() < p ? '$base ${adv()}' : base;
  double amount() =>
      r.nextInt(10) == 0 ? pick(amounts) : r.nextInt(5000000) * 1.0;

  static const stores = ['store_001', 'store_002', 'store_003'];

  List<Product> products(int n) => [
        for (var i = 0; i < n; i++)
          Product(
            id: 'p$i',
            name: maybeAdv('Sản phẩm $i'),
            code: r.nextInt(30) == 0 ? '' : 'MA-$i',
            barcode: r.nextInt(5) == 0
                ? null
                : '8930000${i.toString().padLeft(6, '0')}',
            brand: r.nextInt(4) == 0 ? null : 'Brand ${i % 40}',
            price: amount(),
            costPrice: amount(),
            branchStocks: {
              for (final s in stores)
                s: r.nextInt(8) == 0 ? -r.nextInt(50) : r.nextInt(1000),
            },
            category: switch (r.nextInt(6)) {
              0 => '',
              1 => 'Nhóm ${i % 30} >> Con ${i % 7} >> Cháu ${i % 3}',
              2 => adv(),
              _ => 'Nhóm ${i % 30}',
            },
            minStock: r.nextBool() ? null : r.nextInt(20),
            isCombo: r.nextInt(50) == 0,
            type: r.nextInt(40) == 0 ? 'Dịch vụ' : null,
          ),
      ];

  List<Customer> customers(int n) => [
        for (var i = 0; i < n; i++)
          Customer(
            id: 'c$i',
            name: maybeAdv('Khách hàng $i'),
            phone:
                r.nextInt(10) == 0 ? '' : '090${i.toString().padLeft(7, '0')}',
            email: r.nextInt(3) == 0 ? '' : 'k$i@example.com',
            address: maybeAdv('Địa chỉ $i', p: .2),
            purchases: const [],
            branch: pick(stores),
            createdAt:
                r.nextInt(8) == 0 ? null : '2026-0${1 + i % 9}-01 10:00:00',
            currentDebt: r.nextInt(4) == 0 ? null : amount(),
            totalSales: r.nextInt(4) == 0 ? null : amount(),
            netSales: amount(),
            notes: r.nextInt(4) == 0 ? adv() : null,
          ),
      ];

  List<Supplier> suppliers(int n) => [
        for (var i = 0; i < n; i++)
          Supplier(
            id: 'NCC$i',
            code: 'NCC${i.toString().padLeft(6, '0')}',
            name: maybeAdv('Nhà cung cấp $i'),
            phone: r.nextInt(5) == 0
                ? ''
                : '028392${i.toString().padLeft(5, '0')}',
            email: r.nextInt(3) == 0 ? '' : 's$i@x.vn',
            address: maybeAdv('Địa chỉ $i'),
            totalPurchase: amount(),
            currentDebt: amount(),
            note: r.nextInt(4) == 0 ? adv() : null,
          ),
      ];

  List<UserAccount> accounts(int n) => [
        for (var i = 0; i < n; i++)
          UserAccount(
              username: 'user_$i${r.nextInt(5) == 0 ? longWord : ''}',
              displayName: maybeAdv('Nhân viên $i', p: .3),
              role: pick(['admin', 'supervisor', 'nhanvien']),
              storeId: pick([...stores, 'all'])),
      ];

  /// modes: normal, zeros, outlier, equal, single, negative, nan
  RevenueSummary revenue(int days, {String mode = 'normal', DateTime? start}) {
    final s = start ?? DateTime(2026, 1, 1);
    double v(int i) => switch (mode) {
          'zeros' => 0,
          'outlier' => i == days ~/ 2 ? 1e12 : r.nextInt(5000000) * 1.0,
          'equal' => 1234567,
          'negative' => max(0, 90000000.0 - i * 250000 * (1 + r.nextDouble())) -
              (i > days ~/ 2 ? 500000 : 0),
          'nan' =>
            i % 3 == 0 ? double.nan : (i % 3 == 1 ? double.infinity : 1000.0),
          _ => r.nextInt(90000000) * 1.0,
        };
    final n = mode == 'single' ? 1 : days;
    final reps = [
      for (var i = 0; i < n; i++)
        RevenueReport(
          date: s.add(Duration(days: i)),
          totalRevenue: v(i),
          totalCost: v(i) / 2,
          profit: v(i) / 2,
          totalOrders: mode == 'zeros' ? 0 : r.nextInt(200),
          totalItemsSold: mode == 'zeros' ? 0 : r.nextInt(2000),
          storeRevenues: {for (final st in stores) st: v(i) / 3},
          productRevenues: [
            if (mode != 'zeros')
              for (var p = 0; p < 8; p++)
                ProductRevenue(
                    productId: 'p$p',
                    productName: maybeAdv('Sản phẩm $p'),
                    quantitySold: r.nextInt(100),
                    revenue: v(i) / 8,
                    cost: v(i) / 16,
                    profit: v(i) / 16,
                    profitMargin: mode == 'nan' ? double.nan : 50),
          ],
        ),
    ];
    double sum(double Function(RevenueReport) f) =>
        reps.fold(0.0, (a, b) => a + f(b));
    return RevenueSummary(
      startDate: s,
      endDate: s.add(Duration(days: max(0, n - 1))),
      totalRevenue: sum((e) => e.totalRevenue),
      totalCost: sum((e) => e.totalCost),
      totalProfit: sum((e) => e.profit),
      totalOrders: reps.fold(0, (a, b) => a + b.totalOrders),
      totalItemsSold: reps.fold(0, (a, b) => a + b.totalItemsSold),
      dailyReports: reps,
    );
  }
}

// ------------------------------------------------------------------- host
Widget stressHost(Widget home, List<Override> overrides,
    {double textScale = 1, bool dark = false, bool rtlDir = false}) {
  return ProviderScope(
    key: UniqueKey(),
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: dark ? ThemeData.dark(useMaterial3: true) : AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('vi'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: Directionality(
            textDirection: rtlDir ? TextDirection.rtl : TextDirection.ltr,
            child: child!),
      ),
      home: home,
    ),
  );
}

/// First exception text (or null) - drains ALL queued exceptions.
String? drain(WidgetTester t) {
  String? first;
  Object? e;
  while ((e = t.takeException()) != null) {
    first ??= e.toString().split('\n').first;
  }
  return first;
}

void expectClean(WidgetTester t, [String ctx = '']) {
  final e = drain(t);
  if (e != null) fail('[$ctx] $e');
}

/// Registers: every device (text scale rotating, theme alternating, role
/// alternating) + every text scale on 360x640 and 1280x720.
/// [check] runs after settle (lazy-list asserts, etc.).
void stressMatrix(
  String name,
  Widget Function() page,
  List<Override> Function(UserAccount u) overrides, {
  int rot = 0,
  bool dark = true,
  Future<void> Function(WidgetTester t, Dev d)? check,
  int? maxMs,
}) {
  Future<void> run(
      WidgetTester t, Dev d, double scale, UserAccount u, bool isDark) async {
    setDevice(t, d);
    debugErrors();
    addTearDown(t.view.reset);
    final sw = Stopwatch()..start();
    await t.pumpWidget(
        stressHost(page(), overrides(u), textScale: scale, dark: isDark));
    await t.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 20));
    sw.stop();
    expectClean(t, '$name ${d.name} x$scale ${u.role}');
    if (check != null) await check(t, d);
    expectClean(t, '$name check');
    debugPrint('STRESS $name @${d.name} x$scale dark=$isDark '
        '${u.role}: ${sw.elapsedMilliseconds}ms');
    if (maxMs != null) {
      expect(sw.elapsedMilliseconds, lessThan(maxMs),
          reason: 'cold build+settle too slow');
    }
  }

  for (var i = 0; i < devices.length; i++) {
    final d = devices[i];
    final scale = textScales[(i + rot) % textScales.length];
    final u = i.isEven ? sweepAdmin : sweepStaff;
    final isDark = dark && i % 3 == 2;
    testWidgets('$name @${d.name} x$scale ${u.role}${isDark ? ' dark' : ''}',
        (t) => run(t, d, scale, u, isDark));
  }
  // worst case corners: smallest screen with the largest text, landscape tiny
  for (final c in [
    (devices[0], 2.0),
    (devices[0], 1.0),
    (devices[1], 2.0),
    (devices[7], 2.0),
  ]) {
    testWidgets('$name @${c.$1.name} corner x${c.$2}',
        (t) => run(t, c.$1, c.$2, sweepStaff, false));
  }
  for (final d in [devices[3], devices[11]]) {
    for (final s in textScales) {
      testWidgets('$name @${d.name} scale-sweep x$s',
          (t) => run(t, d, s, sweepAdmin, false));
    }
  }
}

/// Counts built rows of [type].
int built(Type type) =>
    find.byType(type, skipOffstage: false).evaluate().length;

/// With STRESS_DEBUG=1 prints location of each framework error.
void debugErrors() {
  if (Platform.environment['STRESS_DEBUG'] != '1') return;
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    if (Platform.environment['STRESS_FULL'] == '1') debugPrint(d.toString());
    final lines = d.toString().split('\n');
    final k = lines.indexWhere((l) => l.contains('error-causing widget'));
    debugPrint(
        'STRESSERR ${lines.firstWhere((l) => l.contains('overflowed') || l.contains('Exception') || l.contains('Error'), orElse: () => lines.first)} @ ${k >= 0 ? lines.skip(k + 1).take(3).join(' ') : ''}');
    prev?.call(d);
  };
  addTearDown(() => FlutterError.onError = prev);
}

/// Opens [builder] via showDialog (or a scroll-controlled modal sheet) right
/// after the first frame so dialogs are tested under real route constraints.
class Opener extends StatefulWidget {
  const Opener(this.builder, {super.key, this.sheet = false});
  final WidgetBuilder builder;
  final bool sheet;
  @override
  State<Opener> createState() => _OpenerState();
}

class _OpenerState extends State<Opener> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.sheet) {
        showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            builder: widget.builder);
      } else {
        showDialog<void>(context: context, builder: widget.builder);
      }
    });
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: SizedBox.expand());
}
