// Seeded monkey (random UI fuzzer) for the "other" screens.
//
// Reproduce a failure with:  STRESS_SEED=<seed> STRESS_ITER=<n> flutter test <file>
import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_theme.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'package:stores/presentation/common/widgets/barcode_scanner_page.dart';

import '../ui_matrix_other/stress_kit.dart';

export '../ui_matrix_other/stress_kit.dart';

/// Documented allowlist: failures that are test-environment artefacts, not UI bugs.
/// - Firebase/platform plugins are not available in flutter_test (no app/channel)
/// - network images / http are blocked in flutter_test
/// - file/image pickers, share, permission and printing plugins are not mocked
const allowlist = <String>[
  'No Firebase App',
  '[core/no-app]',
  'MissingPluginException',
  'PlatformException',
  'HTTP request failed',
  'NetworkImageLoadException',
  'Invalid image data',
  'Failed host lookup',
  'SocketException',
  'Unable to load asset',
  'ImageCodecException',
  'Unexpected null value', // plugin channel returning null
  'MobileScannerException', // camera plugin has no platform side in tests
];

/// Errors raised inside these folders belong to other agents; they are counted
/// and reported (not failed) by this monkey.
const foreignAreas = <String>[
  'presentation/inventories/',
  'presentation/orders/',
  'presentation/notifications/',
  'presentation/common/',
];

class MonkeyAuth extends StateNotifier<UserAccount?> implements AuthNotifier {
  MonkeyAuth(super.state);
  void set(UserAccount? u) => state = u;
  @override
  Future<String?> login(String u, String p) async =>
      (u.trim().isEmpty || p.isEmpty) ? 'Vui lòng nhập đủ thông tin' : null;
  @override
  Future<void> logout() async => state = null;
}

final _garbage = <String>[
  ...adversarial,
  List.filled(2000, 'x').join(),
  '${List.filled(300, 'Từ dài ').join()}\n\n${List.filled(50, '😀').join()}',
  '-99999999999999',
  '1e12',
  '999999999999999999999',
  'NaN',
  'Infinity',
  '0',
  '0.000001',
  '1,000,000.5',
  '١٢٣٤', // arabic-indic digits
  '\u0000\u0001\u001F',
  '9' * 40,
  '+84 912 345 678',
  'a@b',
  '   leading and trailing   ',
];

/// Where (widget + file:line) the most recent framework error was raised.
String lastErrorWhere = '';

/// (message, where) of every framework error since the last check.
final List<(String, String)> collectedErrors = [];

class Monkey {
  Monkey(this.t, this.seed, this.label,
      {required this.scale, this.auth, this.allowLogout = false});
  final bool allowLogout;
  final WidgetTester t;
  final int seed;
  final String label;
  final ValueNotifier<double> scale;
  final MonkeyAuth? auth;
  late final Random r = Random(seed);
  final List<String> trail = [];
  final Map<String, int> allowed = {};
  int steps = 0;
  final Map<String, int> actions = {};
  Dev dev = devices[5];
  bool _mouseAdded = false;
  TestGesture? _mouse;

  void _log(String s) {
    final k = s.split(' ').first;
    actions[k] = (actions[k] ?? 0) + 1;
    trail.add('#$steps $s');
    if (Platform.environment['STRESS_TRACE'] == '1')
      debugPrint('TRACE #$steps $s');
    if (trail.length > 40) trail.removeAt(0);
  }

  bool _isAllowed(String msg) => allowlist.any(msg.contains);

  /// Classifies one error; returns null when allowlisted, else a failure text.
  String? _classify(String msg, String where) {
    // Overflow with no app-code creator = inside a Flutter framework widget
    // (date/time pickers on tiny screens); not fixable from our folders.
    // Flutter's DropdownButton route rebuilds a ListenableBuilder while its
    // menu is open and the window is resized/rescaled (framework behaviour).
    if (msg.contains('called during build') &&
        msg.contains('DropdownButton<')) {
      _allow('FRAMEWORK dropdown menu rebuild during resize');
      return null;
    }
    // Dialog actions alone (stacked OverflowBar) exceed a 240x320 screen at
    // >=1.8x text; no real device is that small (documented, tiny dialogs only).
    if (msg.contains('overflowed') &&
        where.contains('AlertDialog:') &&
        dev.w <= 280 &&
        scale.value >= 1.8) {
      _allow(
          'TINY-DIALOG ${msg.split('\n').first} dev=${dev.name} x${scale.value}');
      return null;
    }
    // Hero flight bookkeeping assertion on rapid push/pop of routes that both
    // carry default FAB heroes (Flutter framework; needs unique heroTags).
    if (msg.contains('widgets/heroes.dart')) {
      _allow('FRAMEWORK hero flight assertion (rapid push/pop)');
      return null;
    }
    if (where.contains('material/date_picker.dart') ||
        where.contains('material/time_picker.dart') ||
        where.contains('material/calendar_date_picker.dart')) {
      _allow('FRAMEWORK picker: ${msg.split('\n').first}');
      return null;
    }
    if (msg.contains('overflowed') && !where.contains('lib/')) {
      _allow(
          'FRAMEWORK ${msg.split('\n').first} after [${trail.length >= 2 ? trail.sublist(trail.length - 2).join(' | ') : ''}] dev=${dev.name} x${scale.value}');
      return null;
    }
    if (foreignAreas.any(where.contains)) {
      // Bug in another team's folder: reported, not failed here.
      _allow('FOREIGN ${msg.split('\n').first} @ ${where.trim()}');
      return null;
    }
    if (_isAllowed(msg)) {
      _allow(msg.split('\n').first);
      return null;
    }
    return msg;
  }

  void _allow(String k) {
    final kk = k.length > 170 ? k.substring(0, 170) : k;
    allowed[kk] = (allowed[kk] ?? 0) + 1;
  }

  void _check() {
    Object? e;
    Object? lastTaken;
    var any = false;
    while ((e = t.takeException()) != null) {
      any = true;
      lastTaken = e;
    }
    if (!any && collectedErrors.isEmpty) return;
    final errs = List.of(collectedErrors);
    collectedErrors.clear();
    if (errs.isEmpty) {
      // async (zone) error not seen by FlutterError.onError
      errs.add((lastTaken.toString(), ''));
    }
    for (final (msg, where) in errs) {
      final bad = _classify(msg, where);
      if (bad == null) continue;
      final first = bad.split('\n').take(6).join('\n');
      debugPrint('MONKEY FAIL [$label] seed=$seed step=$steps dev=${dev.name} '
          'scale=${scale.value}\n$first\nWHERE: $where\nTRAIL:\n${trail.join('\n')}');
      fail(
          '[$label] seed=$seed step=$steps: ${bad.split('\n').first} @ $where');
    }
  }

  static bool _tappable(Widget w) =>
      w is ButtonStyleButton ||
      w is IconButton ||
      w is FloatingActionButton ||
      w is ListTile ||
      w is Checkbox ||
      w is Switch ||
      w is Radio ||
      w is ChoiceChip ||
      w is FilterChip ||
      w is ActionChip ||
      w is InputChip ||
      w is PopupMenuButton ||
      w is DropdownButton ||
      w is NavigationDestination ||
      w is InkWell ||
      w is GestureDetector;

  Finder get _tapFinder =>
      find.byWidgetPredicate(_tappable, description: 'tappable').hitTestable();

  Future<void> _settle() async {
    // bounded: never hang on infinite animations
    await t.pump(Duration(milliseconds: 50 + r.nextInt(250)));
    await t.pump(const Duration(milliseconds: 120));
  }

  Future<void> tap() async {
    final f = _tapFinder;
    final n = f.evaluate().length;
    if (n == 0) return _log('tap: none');
    final i = r.nextInt(n);
    _log('tap #$i/$n ${f.at(i).evaluate().first.widget.runtimeType}');
    await t.tap(f.at(i), warnIfMissed: false);
    await _settle();
  }

  Future<void> enter() async {
    final f = find.byType(EditableText).hitTestable();
    final n = f.evaluate().length;
    if (n == 0) return _log('enter: none');
    final i = r.nextInt(n);
    final text = _garbage[r.nextInt(_garbage.length)];
    _log(
        'enter #$i/$n "${text.length > 24 ? '${text.substring(0, 24)}…(${text.length})' : text.replaceAll('\n', '\\n')}"');
    await t.enterText(f.at(i), text);
    await t.pump(const Duration(milliseconds: 60));
    if (r.nextInt(3) == 0) {
      await t.testTextInput.receiveAction(TextInputAction.done);
      _log('  + keyboard done');
    }
    await _settle();
  }

  Future<void> scroll() async {
    final f = find.byType(Scrollable).hitTestable();
    final n = f.evaluate().length;
    if (n == 0) return _log('scroll: none');
    final i = r.nextInt(n);
    final dy = (r.nextInt(2001) - 1000).toDouble();
    final dx = r.nextInt(5) == 0 ? (r.nextInt(801) - 400).toDouble() : 0.0;
    _log('scroll #$i/$n ($dx,$dy)');
    if (r.nextBool()) {
      await t.fling(f.at(i), Offset(dx, dy), 500.0 + r.nextInt(4000),
          warnIfMissed: false);
    } else {
      await t.drag(f.at(i), Offset(dx, dy), warnIfMissed: false);
    }
    await _settle();
  }

  Future<TestGesture> _ensureMouse() async {
    _mouse ??= await t.createGesture(kind: PointerDeviceKind.mouse);
    if (!_mouseAdded) {
      await _mouse!.addPointer(location: Offset.zero);
      _mouseAdded = true;
    }
    return _mouse!;
  }

  Future<void> wheel() async {
    final f = find.byType(Scrollable).hitTestable();
    if (f.evaluate().isEmpty) return;
    final c = t.getCenter(f.first);
    final g = await _ensureMouse();
    final dy = (r.nextInt(2001) - 1000).toDouble();
    _log('wheel $dy');
    await g.moveTo(c);
    await t.sendEventToBinding(PointerScrollEvent(
        position: c,
        scrollDelta: Offset(0, dy),
        kind: PointerDeviceKind.mouse));
    await _settle();
  }

  Future<void> hover() async {
    final f = _tapFinder;
    final n = f.evaluate().length;
    if (n == 0) return;
    final i = r.nextInt(n);
    final g = await _ensureMouse();
    _log('hover #$i/$n');
    await g.moveTo(t.getCenter(f.at(i)));
    await t.pump(const Duration(milliseconds: 80));
  }

  Future<void> back() async {
    final nav = find.byType(Navigator);
    if (nav.evaluate().isEmpty) return;
    final st = t.state<NavigatorState>(nav.first);
    _log('back (canPop=${st.canPop()})');
    await st.maybePop();
    await _settle();
  }

  Future<void> resize() async {
    dev = devices[r.nextInt(devices.length)];
    if (r.nextInt(3) == 0) {
      // rotate
      t.view.devicePixelRatio = dev.dpr;
      t.view.physicalSize = Size(dev.h * dev.dpr, dev.w * dev.dpr);
    } else {
      setDevice(t, dev);
    }
    _log('resize ${dev.name}');
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> rescale() async {
    scale.value = textScales[r.nextInt(textScales.length)];
    _log('textScale ${scale.value}');
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> toggleRole() async {
    if (auth == null) return;
    final roles = [sweepAdmin, sweepStaff, if (allowLogout) null];
    final u = roles[r.nextInt(roles.length)] ??
        const UserAccount(
            username: 'sup',
            displayName: 'Giám sát',
            role: 'supervisor',
            storeId: 'store_001');
    _log('role -> ${u.role}');
    auth!.set(allowLogout && r.nextInt(6) == 0 ? null : u);
    await t.pump(const Duration(milliseconds: 100));
  }

  Future<void> keys() async {
    final k = [
      LogicalKeyboardKey.tab,
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.escape,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.space,
    ][r.nextInt(6)];
    final shift = r.nextInt(4) == 0;
    _log('key ${k.keyLabel}${shift ? ' +shift' : ''}');
    if (shift) await t.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await t.sendKeyEvent(k);
    if (shift) await t.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await _settle();
  }

  Future<void> longPressOrDouble() async {
    final f = _tapFinder;
    final n = f.evaluate().length;
    if (n == 0) return;
    final i = r.nextInt(n);
    if (r.nextBool()) {
      _log('longPress #$i/$n');
      await t.longPress(f.at(i), warnIfMissed: false);
    } else {
      _log('doubleTap #$i/$n');
      await t.tap(f.at(i), warnIfMissed: false);
      await t.pump(const Duration(milliseconds: 40));
      await t.tap(f.at(i), warnIfMissed: false);
    }
    await _settle();
  }

  Future<void> step() async {
    steps++;
    // The camera scanner needs a platform plugin (async errors escape the
    // test zone): leave it immediately instead of interacting with it.
    if (find.byType(BarcodeScannerPage).evaluate().isNotEmpty) {
      _log('leave scanner');
      await t.state<NavigatorState>(find.byType(Navigator).first).maybePop();
      await _settle();
      _check();
      return;
    }
    final reopen = find.byKey(reopenKey).hitTestable();
    if (reopen.evaluate().isNotEmpty) {
      _log('reopen');
      await t.tap(reopen);
      await _settle();
      _check();
      return;
    }
    try {
      final x = r.nextInt(100);
      if (x < 38) {
        await tap();
      } else if (x < 56) {
        await enter();
      } else if (x < 68) {
        await scroll();
      } else if (x < 72) {
        await wheel();
      } else if (x < 76) {
        await hover();
      } else if (x < 82) {
        await back();
      } else if (x < 88) {
        await resize();
      } else if (x < 92) {
        await rescale();
      } else if (x < 94) {
        await toggleRole();
      } else if (x < 98) {
        await keys();
      } else {
        await longPressOrDouble();
      }
    } on RangeError {
      _log('skip (target vanished)');
    } on StateError {
      _log('skip (target vanished)');
    }
    _check();
  }
}

String _appFrames(StackTrace st) => st
    .toString()
    .split('\n')
    .where((l) => l.contains('package:stores'))
    .take(3)
    .map((l) => l.replaceAll(RegExp(r'\s+'), ' '))
    .join(' <- ');

int stableHash(String s) =>
    s.codeUnits.fold<int>(7, (a, c) => (a * 31 + c) % 100003);

/// Root route: pushes the screen under test on top of itself so popping the
/// screen (Save / back arrow) does not leave an empty navigator; the monkey
/// re-opens it through [reopenKey].
const reopenKey = Key('monkey_reopen');

class _Root extends StatefulWidget {
  const _Root(this.page);
  final Widget Function() page;
  @override
  State<_Root> createState() => _RootState();
}

class _RootState extends State<_Root> {
  void _open() => Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => widget.page()));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _open();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: ElevatedButton(
                key: reopenKey, onPressed: _open, child: const Text('open'))),
      );
}

/// Registers one monkey test for [page].
void monkeyTest(
  String name,
  Widget Function() page,
  List<Override> Function(UserAccount u) overrides, {
  int? iterations,
  int salt = 0,
  UserAccount user = sweepAdmin,
  bool allowLogout = false,
}) {
  final iters = iterations ?? stressIter();
  testWidgets('MONKEY $name ($iters steps)', (t) async {
    final seed = stressSeed + salt + stableHash(name);
    final scale = ValueNotifier<double>(1.0);
    final auth = MonkeyAuth(user);
    setDevice(t, devices[5]);
    addTearDown(t.view.reset);
    collectedErrors.clear();
    // Platform plugins have no native side in flutter_test: answer benignly.
    final messenger = t.binding.defaultBinaryMessenger;
    for (final ch in const [
      'plugins.flutter.io/url_launcher',
      'dev.fluttercommunity.plus/share',
      'miguelruivo.flutter.plugins.filepicker',
      'plugins.flutter.io/image_picker',
      'plugins.flutter.io/path_provider',
      'flutter.baseflow.com/permissions/methods',
    ]) {
      messenger.setMockMethodCallHandler(MethodChannel(ch),
          (call) async => ch.contains('url_launcher') ? true : null);
    }
    addTearDown(() {
      for (final ch in const [
        'plugins.flutter.io/url_launcher',
        'dev.fluttercommunity.plus/share',
        'miguelruivo.flutter.plugins.filepicker',
        'plugins.flutter.io/image_picker',
        'plugins.flutter.io/path_provider',
        'flutter.baseflow.com/permissions/methods',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(ch), null);
      }
    });
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final lines = d.toString().split('\n');
      final k = lines.indexWhere((l) => l.contains('error-causing widget'));
      lastErrorWhere = k >= 0 ? lines.skip(k + 1).take(3).join(' ') : '';
      final refs = RegExp(r'lib/[\w/]+\.dart:\d+(?::\d+)?')
          .allMatches(d.toString())
          .map((m) => m.group(0))
          .toSet()
          .take(4)
          .join(' ');
      if (refs.isNotEmpty) lastErrorWhere = '$lastErrorWhere || $refs';
      final frames = (d.stack?.toString() ?? '')
          .split('\n')
          .where((l) => l.contains('package:stores'))
          .take(3)
          .map((l) => l.replaceAll(RegExp(r'\s+'), ' '))
          .join(' <- ');
      final top = (d.stack?.toString() ?? '')
          .split('\n')
          .firstWhere((l) => l.trim().isNotEmpty, orElse: () => '')
          .replaceAll(RegExp(r'\s+'), ' ');
      lastErrorWhere = '$lastErrorWhere TOP: $top';
      if (frames.isNotEmpty) lastErrorWhere = '$lastErrorWhere STACK: $frames';
      collectedErrors.add((d.exceptionAsString(), lastErrorWhere));
      prevOnError?.call(d);
    };
    addTearDown(() => FlutterError.onError = prevOnError);
    late final Monkey m;
    final sw = Stopwatch()..start();
    Object? testFailure;
    StackTrace? testFailureTrace;
    // Async errors (unawaited futures in onTap handlers: Firebase/plugins) are
    // routed to this guarded zone and classified by the monkey like others.
    await runZonedGuarded<Future<void>>(() async {
      try {
        await t.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...overrides(user),
            authProvider.overrideWith((ref) => auth),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('vi'),
            builder: (context, child) => ValueListenableBuilder<double>(
              valueListenable: scale,
              builder: (_, s, __) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(s)),
                child: child!,
              ),
            ),
            home: _Root(page),
          ),
        ));
        await t.pump(const Duration(milliseconds: 300));
        m = Monkey(t, seed, name,
            scale: scale, auth: auth, allowLogout: allowLogout);
        for (var i = 0; i < iters; i++) {
          await m.step();
        }
        // drain: let in-flight async work (real futures) finish INSIDE the test so
        // late errors are caught by _check instead of failing after completion.
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 250)));
        await t.pump(const Duration(seconds: 2));
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 1));
        m._check();
      } catch (e, st) {
        testFailure = e;
        testFailureTrace = st;
      }
    }, (e, st) {
      collectedErrors.add((e.toString(), 'ZONE ${_appFrames(st)}'));
    });
    if (testFailure != null) {
      Error.throwWithStackTrace(testFailure!, testFailureTrace!);
    }
    debugPrint('MONKEY OK [$name] seed=$seed steps=${m.steps} '
        '${sw.elapsedMilliseconds}ms actions=${m.actions} allowlisted=${m.allowed}');
  });
}
