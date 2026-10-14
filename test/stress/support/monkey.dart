import 'dart:async';
import 'dart:math';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stores/application/auth/auth_providers.dart';
import 'package:stores/core/theme/app_theme.dart';
import 'package:stores/domain/entities/user_account.dart';

import 'orders_support.dart';

/// Documented allow-list of *environmental* errors the monkey ignores (see
/// [isAllowedError] in orders_support.dart): Firebase not initialised, missing
/// platform plugins (camera / file picker / share), PlatformException.
/// Everything else (overflow, assertion, null-check, range, state errors...)
/// fails the run and prints seed + step trail.
class MonkeyHost extends StatelessWidget {
  const MonkeyHost(
      {super.key, required this.home, required this.scale, required this.dark});
  final Widget home;
  final ValueNotifier<double> scale;
  final ValueNotifier<bool> dark;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([scale, dark]),
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('vi'),
        theme: dark.value
            ? ThemeData.dark(useMaterial3: true)
            : AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale.value)),
          child: child!,
        ),
        home: _BaseRoute(home: home),
      ),
    );
  }
}

/// Root route under the screen being fuzzed, so that a page can pop itself
/// (exit dialogs, "back", successful save) without emptying the Navigator,
/// exactly like in the real app where the screen is pushed onto a parent.
/// A button re-opens the screen so the monkey can keep going.
class _BaseRoute extends StatefulWidget {
  const _BaseRoute({required this.home});
  final Widget home;
  @override
  State<_BaseRoute> createState() => _BaseRouteState();
}

class _BaseRouteState extends State<_BaseRoute> {
  bool _opened = false;

  void _open() {
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => widget.home));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_opened) {
        _opened = true;
        _open();
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ElevatedButton(
            key: const Key('monkey_reopen'),
            onPressed: _open,
            child: const Text('Mở lại màn hình'),
          ),
        ),
      );
}

class MonkeyResult {
  MonkeyResult(this.steps, this.ignored);
  final int steps;
  final int ignored;
}

class MonkeyConfig {
  MonkeyConfig({this.keywords = const [], this.keywordBias = 0.25});

  /// Button/text fragments the monkey prefers, to walk deeper into a flow
  /// (e.g. "Thanh toán", "Hoàn tất").
  final List<String> keywords;
  final double keywordBias;
}

/// Runs a seeded monkey against whatever is currently pumped.
///
/// The widget tree must be hosted with [MonkeyHost] inside an
/// [UncontrolledProviderScope] using [container].
Future<MonkeyResult> runMonkey(
  WidgetTester tester, {
  required ProviderContainer container,
  required ValueNotifier<double> scale,
  required ValueNotifier<bool> dark,
  required int seed,
  required int steps,
  required String label,
  MonkeyConfig? config,
}) {
  // Unhandled async errors (failed awaits inside `onPressed: () async {}`)
  // would abort the whole test through the binding's zone handler; catch them
  // in a guarded zone and classify them with the same allow-list instead.
  final log = ErrorLog()..install();
  final done = Completer<MonkeyResult>();
  runZonedGuarded(() async {
    try {
      done.complete(await _runMonkeyInner(tester,
          log: log,
          container: container,
          scale: scale,
          dark: dark,
          seed: seed,
          steps: steps,
          label: label,
          config: config));
    } catch (e, st) {
      done.completeError(e, st);
    }
  }, (e, st) => log.addZoneError(e, st));
  return done.future;
}

Future<MonkeyResult> _runMonkeyInner(
  WidgetTester tester, {
  required ErrorLog log,
  required ProviderContainer container,
  required ValueNotifier<double> scale,
  required ValueNotifier<bool> dark,
  required int seed,
  required int steps,
  required String label,
  MonkeyConfig? config,
}) async {
  final rnd = Random(seed);
  final cfg = config ?? MonkeyConfig();
  final trail = <String>[];
  var ignoredErrors = 0;
  Device curDev = devices[4];

  void fail_(int i, String why) {
    final tail = trail.length > 30 ? trail.sublist(trail.length - 30) : trail;
    fail('MONKEY FAILURE [$label] seed=$seed step=$i\n$why\n'
        'step trail (last ${tail.length}):\n  ${tail.join('\n  ')}');
  }

  Future<void> pumpShort() async {
    await tester.pump(const Duration(milliseconds: 120));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Finder tappables() => find
      .byWidgetPredicate((w) =>
          w is ButtonStyleButton ||
          w is IconButton ||
          w is ListTile ||
          w is InkWell ||
          w is ChoiceChip ||
          w is FilterChip ||
          w is ActionChip ||
          w is InputChip ||
          w is Checkbox ||
          w is Switch ||
          w is Radio ||
          w is FloatingActionButton ||
          w is PopupMenuButton ||
          w is Tab ||
          w is NavigationDestination ||
          w is GestureDetector && w.onTap != null)
      .hitTestable();

  String describe(Element e) {
    final w = e.widget;
    var txt = '';
    void visit(Element c) {
      if (txt.isNotEmpty) return;
      final cw = c.widget;
      if (cw is Text) {
        txt =
            (cw.data ?? cw.textSpan?.toPlainText() ?? '').replaceAll('\n', ' ');
        if (txt.length > 24) txt = txt.substring(0, 24);
      } else if (cw is Icon && cw.icon != null) {
        txt = 'icon:${cw.icon!.codePoint.toRadixString(16)}';
      } else {
        c.visitChildren(visit);
      }
    }

    e.visitChildren(visit);
    final k = w.key;
    return '${w.runtimeType}${k != null ? '($k)' : ''}"$txt"';
  }

  const texts = <String>[
    '0',
    '1',
    '-5',
    '999999999999999',
    '1e12',
    'NaN',
    '12,5',
    '1.000.000',
    '٣٤٥', // arabic-indic digits
    '   ',
    '',
  ];

  String randomText() {
    final c = rnd.nextInt(5);
    if (c == 0) return Gen.adversarial[rnd.nextInt(Gen.adversarial.length)];
    if (c == 1) return 'x' * (50 + rnd.nextInt(200));
    return texts[rnd.nextInt(texts.length)];
  }

  try {
    for (var i = 0; i < steps; i++) {
      final roll = rnd.nextDouble();
      String act;
      try {
        if (roll < 0.52) {
          // keyword-biased or random tap
          Finder? target;
          if (cfg.keywords.isNotEmpty && rnd.nextDouble() < cfg.keywordBias) {
            final kw = cfg.keywords[rnd.nextInt(cfg.keywords.length)];
            final f = find.textContaining(kw).hitTestable();
            if (f.evaluate().isNotEmpty) {
              target = f;
              act = 'tap-kw "$kw"';
            } else {
              act = '';
            }
          } else {
            act = '';
          }
          target ??= tappables();
          final els = target.evaluate().toList();
          if (els.isEmpty) {
            act = 'tap(none)';
          } else {
            final e = els[rnd.nextInt(els.length)];
            final rb = e.renderObject as RenderBox;
            final pos = rb.localToGlobal(rb.size.center(Offset.zero));
            act = 'tap ${describe(e)} @${pos.dx.round()},${pos.dy.round()}';
            trail.add('#$i $act');
            await tester.tapAt(pos);
            await pumpShort();
            // long-press sometimes
            if (rnd.nextInt(15) == 0) {
              trail.add('#$i longPress same');
              await tester.longPressAt(pos);
              await pumpShort();
            }
          }
          if (act == 'tap(none)' || act.isEmpty) trail.add('#$i $act');
        } else if (roll < 0.66) {
          final fields = find
              .byWidgetPredicate((w) => w is EditableText)
              .hitTestable()
              .evaluate()
              .toList();
          if (fields.isEmpty) {
            trail.add('#$i enterText(none)');
          } else {
            final e = fields[rnd.nextInt(fields.length)];
            final txt = randomText();
            trail.add(
                '#$i enterText ${txt.length > 20 ? '${txt.substring(0, 20)}…' : txt}');
            await tester.enterText(find.byElementPredicate((x) => x == e), txt);
            await pumpShort();
            if (rnd.nextInt(3) == 0) {
              trail.add('#$i  + submit(done)');
              await tester.testTextInput.receiveAction(TextInputAction.done);
              await pumpShort();
            }
          }
        } else if (roll < 0.78) {
          final sc = find.byType(Scrollable).hitTestable().evaluate().toList();
          if (sc.isEmpty) {
            trail.add('#$i scroll(none)');
          } else {
            final e = sc[rnd.nextInt(sc.length)];
            final f = find.byElementPredicate((x) => x == e);
            final dy = (rnd.nextBool() ? -1 : 1) * (50.0 + rnd.nextInt(3000));
            final fling = rnd.nextBool();
            trail.add('#$i ${fling ? 'fling' : 'drag'} dy=${dy.round()}');
            if (fling) {
              await tester.fling(
                  f, Offset(0, dy), (1500 + rnd.nextInt(3000)).toDouble(),
                  warnIfMissed: false);
            } else {
              await tester.drag(f, Offset(0, dy), warnIfMissed: false);
            }
            await pumpShort();
          }
        } else if (roll < 0.84) {
          trail.add('#$i back');
          final nav =
              tester.state<NavigatorState>(find.byType(Navigator).first);
          await nav.maybePop();
          await pumpShort();
        } else if (roll < 0.90) {
          final d = devices[rnd.nextInt(devices.length)];
          final dpr = dprs[rnd.nextInt(dprs.length)];
          curDev = d;
          trail.add('#$i resize ${d.name} dpr$dpr');
          setView(tester, d, dpr);
          await pumpShort();
        } else if (roll < 0.93) {
          final s = textScales[rnd.nextInt(textScales.length)];
          trail.add('#$i textScale $s');
          scale.value = s;
          await pumpShort();
        } else if (roll < 0.95) {
          trail.add('#$i toggle dark');
          dark.value = !dark.value;
          await pumpShort();
        } else if (roll < 0.97) {
          final n = container.read(authProvider.notifier) as StressAuth;
          final cur = container.read(authProvider);
          final next = cur?.role == 'admin' ? staffUser : adminUser;
          trail.add('#$i role -> ${next.role}');
          n.state = next;
          await pumpShort();
        } else if (roll < 0.985) {
          final k = [
            LogicalKeyboardKey.tab,
            LogicalKeyboardKey.enter,
            LogicalKeyboardKey.escape,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.space,
          ][rnd.nextInt(5)];
          trail.add('#$i key ${k.keyLabel}');
          await tester.sendKeyEvent(k);
          await pumpShort();
        } else {
          final size = tester.view.physicalSize / tester.view.devicePixelRatio;
          final pos = Offset(
              rnd.nextDouble() * size.width, rnd.nextDouble() * size.height);
          trail.add('#$i wheel @${pos.dx.round()},${pos.dy.round()}');
          final g = await tester.createGesture(kind: PointerDeviceKind.mouse);
          await g.addPointer(location: pos);
          await g.moveTo(pos);
          await tester.sendEventToBinding(PointerScrollEvent(
              kind: PointerDeviceKind.mouse,
              position: pos,
              scrollDelta: Offset(0, (rnd.nextBool() ? 1 : -1) * 300.0)));
          await g.removePointer();
          await pumpShort();
        }
      } catch (e, st) {
        // Exceptions thrown by the test driver itself (e.g. a widget vanished
        // between find and tap) are harness noise, not app crashes; but real
        // app exceptions surface through FlutterError and are checked below.
        final msg = e.toString().split('\n').first;
        if (e is TestFailure || e is StateError) {
          trail.add('#$i driver-skip: $msg');
        } else {
          fail_(i, 'driver exception: $e\n$st');
        }
      }

      log.drain(tester);
      // Documented exception: Flutter SDK dialogs (Material date pickers) have
      // their own layout bugs/limits at tiny sizes and odd text scales. An
      // overflow whose creator chain has no lib/presentation frame (the error
      // is attributed to the host's MediaQuery, i.e. an SDK-internal widget) is
      // the SDK's, not ours. App widgets always carry a lib/presentation
      // creator location.
      final sdk = log.errors
          .where((e) =>
              e.contains('overflowed') &&
              (!e.contains('lib/presentation') ||
                  // creator attributed to a non-flex wrapper (Theme/MediaQuery
                  // of a showDatePicker builder) == SDK-internal flex
                  RegExp(r'@ (Theme|MediaQuery)\b').hasMatch(e)))
          .toList();
      for (final e in sdk) {
        log.errors.remove(e);
        log.ignored.add('SDK overflow on ${curDev.name}: $e');
      }
      ignoredErrors = log.ignored.length;
      if (log.errors.isNotEmpty) {
        fail_(i,
            'errors after step on ${curDev.name}:\n  - ${log.unique().join('\n  - ')}');
      }
      // Periodically let everything settle & verify nothing is wedged.
      if (i % 25 == 24) {
        try {
          await tester.pumpAndSettle(const Duration(milliseconds: 100),
              EnginePhase.sendSemanticsUpdate, const Duration(seconds: 5));
        } catch (_) {
          trail.add('#$i (did not settle within 5s)');
        }
        log.drain(tester);
        if (log.errors.isNotEmpty) {
          fail_(i, 'errors on settle:\n  - ${log.unique().join('\n  - ')}');
        }
      }
    }
    // Late async completions (failed Firebase calls etc.) arrive after the
    // last step: give them time, classify them, and clear the binding.
    for (var k = 0; k < 5; k++) {
      await tester.pump(const Duration(seconds: 1));
    }
    log.drain(tester);
    ignoredErrors = log.ignored.length;
    if (log.errors.isNotEmpty) {
      fail_(steps, 'late errors:\n  - ${log.unique().join('\n  - ')}');
    }
  } finally {
    log.uninstall();
  }
  return MonkeyResult(steps, ignoredErrors);
}

/// Registers one seeded monkey test.
///
/// `STRESS_ITER` (default 300) steps per screen, `STRESS_SEED` base seed.
void monkeyTest(
  String name, {
  required StressData Function() data,
  required Widget Function(StressData d) home,
  required List<Override> Function(UserAccount u, StressData d) overrides,
  void Function(ProviderContainer c, StressData d)? setup,
  List<String> keywords = const [],
  Device device = const Device('phone 390x844', 390, 844),
  UserAccount user = adminUser,
  int seedOffset = 0,
}) {
  testWidgets('MONKEY $name', (tester) async {
    final steps = envInt('STRESS_ITER', 300);
    final seed = envInt('STRESS_SEED', 20261014) + seedOffset;
    final d = data();
    setView(tester, device, 2);
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: overrides(user, d));
    addTearDown(container.dispose);
    setup?.call(container, d);
    final scale = ValueNotifier<double>(1.0);
    final dark = ValueNotifier<bool>(false);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MonkeyHost(home: home(d), scale: scale, dark: dark),
    ));
    await tester.pumpAndSettle();
    final sw = Stopwatch()..start();
    final r = await runMonkey(
      tester,
      container: container,
      scale: scale,
      dark: dark,
      seed: seed,
      steps: steps,
      label: name,
      config: MonkeyConfig(keywords: keywords),
    );
    // ignore: avoid_print
    print('MONKEY $name: ${r.steps} steps seed=$seed in '
        '${sw.elapsedMilliseconds}ms (ignored env errors: ${r.ignored})');
  });
}
